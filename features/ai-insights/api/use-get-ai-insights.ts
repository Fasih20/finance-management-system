import { toast } from "sonner";
import { useMutation } from "@tanstack/react-query";

export const useGetAiInsights = () => {
  const mutation = useMutation<{ data: string }, Error>({
    mutationFn: async () => {
      const response = await fetch("/api/ai-insights", {
        method: "GET",
        headers: { "Content-Type": "application/json" },
      });

      const body = await response.json() as { data?: string; error?: string };

      if (!response.ok) {
        throw new Error(body?.error ?? "Failed to fetch AI insights");
      }

      return { data: body.data ?? "No insight available." };
    },
    onError: (error) => {
      toast.error(error.message || "Failed to generate AI insights");
    },
  });

  return mutation;
};
