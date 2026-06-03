import { Hono } from "hono";
import { desc, eq } from "drizzle-orm";
import { clerkMiddleware, getAuth } from "@hono/clerk-auth";
import { GoogleGenerativeAI } from "@google/generative-ai";
import { format } from "date-fns";

import { db } from "@/db/drizzle";
import { transactions, accounts, categories } from "@/db/schema";
import { convertAmountFromMiliunits } from "@/lib/utils";

const app = new Hono().get(
  "/",
  clerkMiddleware(),
  async (c) => {
    const auth = getAuth(c);

    if (!auth?.userId) {
      return c.json({ error: "Unauthorized" }, 401);
    }

    // 1. Fetch the user's latest 50 transactions from DB
    const data = await db
      .select({
        date: transactions.date,
        payee: transactions.payee,
        amount: transactions.amount,
        category: categories.name,
      })
      .from(transactions)
      .innerJoin(accounts, eq(transactions.accountId, accounts.id))
      .leftJoin(categories, eq(transactions.categoryId, categories.id))
      .where(eq(accounts.userId, auth.userId))
      .orderBy(desc(transactions.date))
      .limit(50);

    if (data.length === 0) {
      return c.json({
        data: "No transactions found. Please connect a bank account first to generate AI insights.",
      });
    }

    // 2. Format transactions into a readable text block
    const transactionText = data
      .map((t) => {
        const dateStr = format(new Date(t.date), "yyyy-MM-dd");
        const amountDollars = convertAmountFromMiliunits(t.amount);
        const sign = amountDollars >= 0 ? "+" : "";
        const categoryStr = t.category ? ` [${t.category}]` : "";
        return `${dateStr} | ${t.payee}${categoryStr} | ${sign}$${Math.abs(amountDollars).toFixed(2)}`;
      })
      .join("\n");

    // 3. Build the Prompt
    const prompt = `You are a financial advisor. Analyze these recent transactions and give a concise 3-sentence summary of my spending habits and one specific action item to save money:\n\n${transactionText}`;

    // 4. Invoke Google Gemini 1.5 Flash
    try {
      if (!process.env.GEMINI_API_KEY) {
        throw new Error("GEMINI_API_KEY is missing from environment variables.");
      }

      const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
      const model = genAI.getGenerativeModel({ model: "gemini-flash-lite-latest" });

      const result = await model.generateContent(prompt);
      const response = await result.response;
      const insightText = response.text();

      return c.json({ data: insightText });
      
    } catch (err: unknown) {
      console.error("[AI Insights] Gemini invocation failed:", err);
      const message = err instanceof Error ? err.message : "Unknown Gemini error";
      return c.json(
        {
          error: `Gemini invocation failed: ${message}`,
        },
        500,
      );
    }
  },
);

export default app;