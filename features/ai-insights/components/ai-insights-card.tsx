"use client";

import { useState } from "react";
import { Sparkles, RefreshCw, TrendingUp, AlertCircle } from "lucide-react";
import { useGetAiInsights } from "@/features/ai-insights/api/use-get-ai-insights";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export const AiInsightsCard = () => {
  const aiInsights = useGetAiInsights();
  const [hasRequested, setHasRequested] = useState(false);

  const handleClick = () => {
    setHasRequested(true);
    aiInsights.mutate();
  };

  return (
    <Card className="border-none drop-shadow-sm mb-8 overflow-hidden">
      {/* Gradient header strip */}
      <div className="bg-gradient-to-r from-blue-700 via-blue-600 to-indigo-600 px-6 py-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-x-3">
            <div className="flex items-center justify-center size-9 rounded-full bg-white/20 backdrop-blur-sm">
              <Sparkles className="size-5 text-white" />
            </div>
            <div>
              <h2 className="text-white font-semibold text-base leading-tight">
                AI Financial Insights
              </h2>
              <p className="text-blue-100 text-xs mt-0.5">
                Powered by Amazon Bedrock · Claude 3 Haiku
              </p>
            </div>
          </div>
          <Button
            id="get-ai-insights-btn"
            onClick={handleClick}
            disabled={aiInsights.isPending}
            size="sm"
            className="bg-white text-blue-700 hover:bg-blue-50 hover:text-blue-800 font-semibold shadow-sm transition-all duration-200 gap-x-2"
          >
            {aiInsights.isPending ? (
              <>
                <RefreshCw className="size-4 animate-spin" />
                Analyzing…
              </>
            ) : (
              <>
                <Sparkles className="size-4" />
                {hasRequested ? "Refresh Insights" : "Get AI Insights"}
              </>
            )}
          </Button>
        </div>
      </div>

      <CardContent className="p-6">
        {/* Loading skeleton state */}
        {aiInsights.isPending && (
          <div className="space-y-3">
            <div className="flex items-center gap-x-2 mb-4">
              <div className="size-5 rounded-full bg-blue-100 flex items-center justify-center">
                <TrendingUp className="size-3 text-blue-600" />
              </div>
              <span className="text-sm text-muted-foreground font-medium">
                Analyzing your spending patterns…
              </span>
            </div>
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-[92%]" />
            <Skeleton className="h-4 w-[85%]" />
            <Skeleton className="h-4 w-[78%] mt-2" />
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-[60%]" />
          </div>
        )}

        {/* Error state */}
        {aiInsights.isError && !aiInsights.isPending && (
          <div className="flex items-start gap-x-3 rounded-lg bg-red-50 border border-red-100 p-4">
            <AlertCircle className="size-5 text-red-500 mt-0.5 shrink-0" />
            <div>
              <p className="text-sm font-semibold text-red-700">
                Unable to generate insights
              </p>
              <p className="text-xs text-red-600 mt-1 leading-relaxed">
                {aiInsights.error?.message ?? "An unknown error occurred."}
              </p>
            </div>
          </div>
        )}

        {/* Success state — AI insight text */}
        {aiInsights.isSuccess && !aiInsights.isPending && (
          <div className="space-y-4">
            <div className="flex items-center gap-x-2">
              <div className="size-5 rounded-full bg-green-100 flex items-center justify-center">
                <TrendingUp className="size-3 text-green-600" />
              </div>
              <span className="text-sm font-medium text-muted-foreground">
                Analysis complete
              </span>
            </div>
            <div className="rounded-lg bg-gradient-to-br from-blue-50 to-indigo-50 border border-blue-100 p-5">
              <p className="text-sm text-slate-700 leading-relaxed whitespace-pre-wrap">
                {aiInsights.data?.data}
              </p>
            </div>
          </div>
        )}

        {/* Default idle state — no request made yet */}
        {!hasRequested && !aiInsights.isPending && (
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <div className="flex items-center justify-center size-14 rounded-full bg-blue-50 mb-4">
              <Sparkles className="size-7 text-blue-400" />
            </div>
            <p className="text-sm font-medium text-slate-600 mb-1">
              Get personalized financial advice
            </p>
            <p className="text-xs text-muted-foreground max-w-xs leading-relaxed">
              Click <strong>Get AI Insights</strong> to analyze your recent transactions
              and receive a concise summary of your spending habits plus one
              actionable money-saving tip.
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
