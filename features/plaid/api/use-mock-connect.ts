import { toast } from "sonner";
import { useMutation, useQueryClient } from "@tanstack/react-query";

export const useMockConnect = () => {
  const queryClient = useQueryClient();

  const mutation = useMutation<{ ok: boolean; transactionCount: number }, Error>({
    mutationFn: async () => {
      const response = await fetch("/api/plaid/mock-connect", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
      });

      if (!response.ok) {
        const body = await response.json().catch(() => ({})) as { error?: string };
        throw new Error(body?.error ?? "Failed to connect mock bank");
      }

      return response.json() as Promise<{ ok: boolean; transactionCount: number }>;
    },
    onSuccess: ({ transactionCount }) => {
      toast.success(`Mock bank connected! ${transactionCount} transactions generated.`);
      queryClient.invalidateQueries({ queryKey: ["connected-bank"] });
      queryClient.invalidateQueries({ queryKey: ["summary"] });
      queryClient.invalidateQueries({ queryKey: ["transactions"] });
      queryClient.invalidateQueries({ queryKey: ["accounts"] });
      queryClient.invalidateQueries({ queryKey: ["categories"] });
    },
    onError: (error) => {
      toast.error(error.message || "Failed to connect mock bank");
    },
  });

  return mutation;
};
