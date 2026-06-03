import fs from "fs";
import path from "path";
import { neon } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-http";
import * as dotenv from "dotenv";

// Load environment variables from .env file
dotenv.config();

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error("❌ Error: DATABASE_URL is missing from your .env file!");
  process.exit(1);
}

// Initialize Drizzle with Neon
const sql = neon(databaseUrl);
// @ts-ignore
const db = drizzle(sql);

// Import the actual schemas from your project
// Note: Adjust these import paths if your files are named differently
import { accounts, transactions, categories, connectedBanks } from "./db/schema"; 

async function main() {
  console.log("⏳ Starting direct emergency database seed...");

  try {
    // 1. Read the JSON file directly using an absolute path
    const jsonPath = path.join(process.cwd(), "public", "mock-data.json");
    const rawData = fs.readFileSync(jsonPath, "utf-8");
    const mockData = JSON.parse(rawData);

    // 2. Create a mock user ID (Antonio's repo links data to the authenticated Clerk user)
    // For local dev without complex matching, we use a placeholder or check your schema requirements
    const userId = "user_dev_placeholder"; 

    console.log("🧹 Clearing old empty data states...");
    // Optional: clears tables to prevent key constraint errors if you run it multiple times
    await sql`DELETE FROM transactions`;
    await sql`DELETE FROM accounts`;
    await sql`DELETE FROM categories`;
    await sql`DELETE FROM connected_banks`;

    // 3. Insert Mock Connected Bank
    console.log("Creating connected bank reference...");
    const [mockBank] = await db.insert(connectedBanks).values({
      id: "mock_bank_id",
      userId: userId,
      accessToken: "mock_access_token",
    }).returning();

    // 4. Create Mock Account
    console.log("Creating mock checking account...");
    const [mockAccount] = await db.insert(accounts).values({
      id: "mock_account_id",
      name: "Mock Checking Account",
      userId: userId,
      plaidId: "mock_plaid_id",
    }).returning();

    // 5. Extract unique categories from JSON and insert them
    console.log("Creating transaction categories...");
    const uniqueCategoryNames = Array.from(new Set(mockData.map((t: any) => t.categoryName || t.category)));
    const categoryMap: Record<string, string> = {};

    for (const name of uniqueCategoryNames) {
      const cleanName = name as string;
      const [insertedCat] = await db.insert(categories).values({
        id: `cat_${cleanName.toLowerCase().replace(/\s+/g, '_')}`,
        name: cleanName,
        userId: userId,
      }).returning();
      categoryMap[cleanName] = insertedCat.id;
    }

    // 6. Bulk Insert All 50 Transactions
    console.log(`Inserting ${mockData.length} transactions directly into Neon DB...`);
    
    const transactionsToInsert = mockData.map((t: any, index: number) => ({
      id: t.id || `tx_${index}`,
      amount: t.amount,
      payee: t.payee,
      userId: userId,
      accountId: mockAccount.id,
      categoryId: categoryMap[t.categoryName || t.category] || null,
      date: new Date(t.date),
    }));

    await db.insert(transactions).values(transactionsToInsert);

    console.log("✅ SUCCESS! Your Neon Database is fully seeded with 50 transactions.");
    console.log("Refresh your browser tabs now.");
  } catch (error) {
    console.error("❌ Seeding failed with error:", error);
  }
}

main();