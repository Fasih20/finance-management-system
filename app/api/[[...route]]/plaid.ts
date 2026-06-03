import { readFileSync } from "fs";
import { join } from "path";
import { Hono } from "hono";
import { and, eq, isNotNull } from "drizzle-orm";
import { createId } from "@paralleldrive/cuid2";
import { clerkMiddleware, getAuth } from "@hono/clerk-auth";
import { subDays } from "date-fns";


import { db } from "@/db/drizzle";
import {
  accounts,
  categories,
  connectedBanks,
  transactions,
} from "@/db/schema";
import { convertAmountToMiliunits } from "@/lib/utils";

// ---------------------------------------------------------------------------
// Mock data pools for realistic transaction generation
// ---------------------------------------------------------------------------

const MOCK_PAYEES: { payee: string; category: string; isIncome: boolean; minAmount: number; maxAmount: number }[] = [
  { payee: "Monthly Salary",     category: "Income",          isIncome: true,  minAmount: 3500, maxAmount: 5500 },
  { payee: "Freelance Payment",  category: "Income",          isIncome: true,  minAmount: 500,  maxAmount: 2000 },
  { payee: "Rent",               category: "Utilities",       isIncome: false, minAmount: 1200, maxAmount: 2000 },
  { payee: "Walmart",            category: "Food",            isIncome: false, minAmount: 40,   maxAmount: 200  },
  { payee: "Whole Foods Market", category: "Food",            isIncome: false, minAmount: 60,   maxAmount: 180  },
  { payee: "Trader Joe's",       category: "Food",            isIncome: false, minAmount: 30,   maxAmount: 120  },
  { payee: "McDonald's",         category: "Food",            isIncome: false, minAmount: 8,    maxAmount: 30   },
  { payee: "Chipotle",           category: "Food",            isIncome: false, minAmount: 10,   maxAmount: 25   },
  { payee: "Starbucks",          category: "Food",            isIncome: false, minAmount: 5,    maxAmount: 15   },
  { payee: "DoorDash",           category: "Food",            isIncome: false, minAmount: 20,   maxAmount: 60   },
  { payee: "Uber Eats",          category: "Food",            isIncome: false, minAmount: 18,   maxAmount: 55   },
  { payee: "Uber",               category: "Transport",       isIncome: false, minAmount: 8,    maxAmount: 45   },
  { payee: "Lyft",               category: "Transport",       isIncome: false, minAmount: 8,    maxAmount: 40   },
  { payee: "Shell Gas Station",  category: "Transport",       isIncome: false, minAmount: 40,   maxAmount: 90   },
  { payee: "ExxonMobil",         category: "Transport",       isIncome: false, minAmount: 35,   maxAmount: 85   },
  { payee: "Metro Transit",      category: "Transport",       isIncome: false, minAmount: 2,    maxAmount: 10   },
  { payee: "Electric Bill",      category: "Utilities",       isIncome: false, minAmount: 80,   maxAmount: 180  },
  { payee: "Internet Service",   category: "Utilities",       isIncome: false, minAmount: 50,   maxAmount: 100  },
  { payee: "Water Bill",         category: "Utilities",       isIncome: false, minAmount: 30,   maxAmount: 70   },
  { payee: "Netflix",            category: "Entertainment",   isIncome: false, minAmount: 15,   maxAmount: 25   },
  { payee: "Spotify",            category: "Entertainment",   isIncome: false, minAmount: 10,   maxAmount: 15   },
  { payee: "Amazon Prime",       category: "Entertainment",   isIncome: false, minAmount: 15,   maxAmount: 15   },
  { payee: "Cinema Tickets",     category: "Entertainment",   isIncome: false, minAmount: 20,   maxAmount: 60   },
  { payee: "Steam Games",        category: "Entertainment",   isIncome: false, minAmount: 10,   maxAmount: 60   },
  { payee: "CVS Pharmacy",       category: "Healthcare",      isIncome: false, minAmount: 15,   maxAmount: 80   },
  { payee: "Walgreens",          category: "Healthcare",      isIncome: false, minAmount: 10,   maxAmount: 70   },
  { payee: "Doctor Copay",       category: "Healthcare",      isIncome: false, minAmount: 20,   maxAmount: 60   },
  { payee: "Target",             category: "Food",            isIncome: false, minAmount: 30,   maxAmount: 150  },
  { payee: "Costco",             category: "Food",            isIncome: false, minAmount: 80,   maxAmount: 250  },
  { payee: "Apple App Store",    category: "Entertainment",   isIncome: false, minAmount: 1,    maxAmount: 30   },
];

function randomBetween(min: number, max: number): number {
  return Math.random() * (max - min) + min;
}

function randomDateInLast30Days(): Date {
  const now = new Date();
  const daysAgo = Math.floor(Math.random() * 30);
  const hoursAgo = Math.floor(Math.random() * 24);
  return subDays(now, daysAgo);
}

// ---------------------------------------------------------------------------
// Hono app
// ---------------------------------------------------------------------------

const app = new Hono()
  .get(
    "/connected-bank",
    clerkMiddleware(),
    async (c) => {
      const auth = getAuth(c);

      if (!auth?.userId) {
        return c.json({ error: "Unauthorized" }, 401);
      }

      const [connectedBank] = await db
        .select()
        .from(connectedBanks)
        .where(eq(connectedBanks.userId, auth.userId));

      return c.json({ data: connectedBank || null });
    },
  )
  .delete(
    "/connected-bank",
    clerkMiddleware(),
    async (c) => {
      const auth = getAuth(c);

      if (!auth?.userId) {
        return c.json({ error: "Unauthorized" }, 401);
      }

      const [connectedBank] = await db
        .delete(connectedBanks)
        .where(eq(connectedBanks.userId, auth.userId))
        .returning({ id: connectedBanks.id });

      if (!connectedBank) {
        return c.json({ error: "Not found" }, 404);
      }

      await db
        .delete(accounts)
        .where(
          and(
            eq(accounts.userId, auth.userId),
            isNotNull(accounts.plaidId),
          ),
        );

      await db
        .delete(categories)
        .where(
          and(
            eq(categories.userId, auth.userId),
            isNotNull(categories.plaidId),
          ),
        );

      return c.json({ data: connectedBank });
    },
  )
  .post(
    "/mock-connect",
    clerkMiddleware(),
    async (c) => {
      const auth = getAuth(c);

      if (!auth?.userId) {
        return c.json({ error: "Unauthorized" }, 401);
      }

      // Remove any existing mock connection first (idempotent re-connect)
      await db
        .delete(connectedBanks)
        .where(eq(connectedBanks.userId, auth.userId));

      await db
        .delete(accounts)
        .where(eq(accounts.userId, auth.userId));

      // 1. Create mock connected bank record
      await db.insert(connectedBanks).values({
        id: createId(),
        userId: auth.userId,
        accessToken: "mock_access_token",
      });

      // 2. Create mock account
      const [mockAccount] = await db
        .insert(accounts)
        .values({
          id: createId(),
          name: "Mock Checking Account",
          plaidId: null,
          userId: auth.userId,
        })
        .returning();

      // 3. Upsert mock categories (keep existing ones by name, create missing)
      const categoryNames = Array.from(new Set(MOCK_PAYEES.map((p) => p.category)));

      // Delete old mock categories for this user and recreate cleanly
      await db
        .delete(categories)
        .where(eq(categories.userId, auth.userId));

      const newCategories = await db
        .insert(categories)
        .values(
          categoryNames.map((name) => ({
            id: createId(),
            name,
            plaidId: null,
            userId: auth.userId,
          })),
        )
        .returning();

      const categoryMap = new Map(newCategories.map((cat) => [cat.name, cat.id]));

      // 4. Generate 50 mock transactions
      const transactionValues: typeof transactions.$inferInsert[] = [];

      // Ensure at least 2 income entries
      const incomePayees = MOCK_PAYEES.filter((p) => p.isIncome);
      const expensePayees = MOCK_PAYEES.filter((p) => !p.isIncome);

      // Add 2 income entries
      for (let i = 0; i < 2; i++) {
        const pool = incomePayees[i % incomePayees.length];
        const amount = randomBetween(pool.minAmount, pool.maxAmount);
        transactionValues.push({
          id: createId(),
          payee: pool.payee,
          notes: `${pool.payee} - auto generated`,
          amount: convertAmountToMiliunits(amount),
          date: randomDateInLast30Days(),
          accountId: mockAccount.id,
          categoryId: categoryMap.get(pool.category) ?? null,
        });
      }

      // Add 48 expense entries
      for (let i = 0; i < 48; i++) {
        const pool = expensePayees[i % expensePayees.length];
        const amount = randomBetween(pool.minAmount, pool.maxAmount);
        transactionValues.push({
          id: createId(),
          payee: pool.payee,
          notes: `${pool.payee} - auto generated`,
          amount: convertAmountToMiliunits(-amount), // negative = expense
          date: randomDateInLast30Days(),
          accountId: mockAccount.id,
          categoryId: categoryMap.get(pool.category) ?? null,
        });
      }

      // Shuffle for realistic ordering
      transactionValues.sort(() => Math.random() - 0.5);

      await db.insert(transactions).values(transactionValues);

      return c.json({ ok: true, transactionCount: transactionValues.length }, 200);
    },
  )
  .post(
    "/auto-seed",
    clerkMiddleware(),
    async (c) => {
      const auth = getAuth(c);

      if (!auth?.userId) {
        return c.json({ error: "Unauthorized" }, 401);
      }

      // --- Idempotency check: skip if Mock Checking Account already exists ---
      const [existingAccount] = await db
        .select({ id: accounts.id })
        .from(accounts)
        .where(
          and(
            eq(accounts.userId, auth.userId),
            eq(accounts.name, "Mock Checking Account"),
          ),
        )
        .limit(1);

      if (existingAccount) {
        return c.json({ seeded: false, reason: "already_seeded" }, 200);
      }

      // --- Read mock-data.json from /public ---
      type MockTransaction = {
        id: string;
        payee: string;
        amount: number;
        date: string;
        categoryName: string;
      };

      let mockTransactions: MockTransaction[] = [];
      try {
        const raw = readFileSync(
          join(process.cwd(), "public", "mock-data.json"),
          "utf-8",
        );
        mockTransactions = JSON.parse(raw) as MockTransaction[];
      } catch {
        return c.json({ error: "Failed to read mock-data.json" }, 500);
      }

      // --- Create connectedBank entry ---
      await db
        .delete(connectedBanks)
        .where(eq(connectedBanks.userId, auth.userId));

      await db.insert(connectedBanks).values({
        id: createId(),
        userId: auth.userId,
        accessToken: "mock_access_token",
      });

      // --- Create Mock Checking Account ---
      const [mockAccount] = await db
        .insert(accounts)
        .values({
          id: createId(),
          name: "Mock Checking Account",
          plaidId: null,
          userId: auth.userId,
        })
        .returning();

      // --- Collect all unique category names from the JSON ---
      const categoryNames = Array.from(
        new Set(mockTransactions.map((t) => t.categoryName)),
      );

      // Remove any existing categories for this user, then recreate
      await db
        .delete(categories)
        .where(eq(categories.userId, auth.userId));

      const newCategories = await db
        .insert(categories)
        .values(
          categoryNames.map((name) => ({
            id: createId(),
            name,
            plaidId: null,
            userId: auth.userId,
          })),
        )
        .returning();

      const categoryMap = new Map(newCategories.map((cat) => [cat.name, cat.id]));

      // --- Build and insert transaction rows ---
      const transactionRows: typeof transactions.$inferInsert[] =
        mockTransactions.map((t) => ({
          id: createId(), // generate fresh DB id — JSON id is just reference
          payee: t.payee,
          notes: `${t.payee} — seeded from mock-data.json`,
          amount: t.amount,
          date: new Date(t.date),
          accountId: mockAccount.id,
          categoryId: categoryMap.get(t.categoryName) ?? null,
        }));

      await db.insert(transactions).values(transactionRows);

      return c.json(
        { seeded: true, transactionCount: transactionRows.length },
        200,
      );
    },
  );

export default app;
