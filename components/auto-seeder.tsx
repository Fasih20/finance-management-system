"use client";

import { useEffect, useRef } from "react";
import { useQueryClient } from "@tanstack/react-query";

/**
 * Invisible component — renders null.
 * On mount it silently calls POST /api/plaid/auto-seed.
 * If the user already has data it's a no-op (backend returns { seeded: false }).
 * If data is missing it seeds from mock-data.json and invalidates all queries
 * so the dashboard charts/tables populate automatically.
 */
export const AutoSeeder = () => {
  const queryClient = useQueryClient();
  const hasRun = useRef(false);

  useEffect(() => {
    // Guard: only run once per mount even in React StrictMode double-invoke
    if (hasRun.current) return;
    hasRun.current = true;

    const seed = async () => {
      try {
        const response = await fetch("/api/plaid/auto-seed", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
        });

        if (!response.ok) return; // silently swallow errors

        const body = await response.json() as { seeded: boolean };

        // Only invalidate if new data was actually written
        if (body.seeded) {
          await Promise.all([
            queryClient.invalidateQueries({ queryKey: ["summary"] }),
            queryClient.invalidateQueries({ queryKey: ["transactions"] }),
            queryClient.invalidateQueries({ queryKey: ["accounts"] }),
            queryClient.invalidateQueries({ queryKey: ["categories"] }),
            queryClient.invalidateQueries({ queryKey: ["connected-bank"] }),
          ]);
        }
      } catch {
        // Completely silent — never show a toast or error for auto-seeding
      }
    };

    seed();
  }, [queryClient]);

  return null;
};
