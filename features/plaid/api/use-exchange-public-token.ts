// This hook is no longer used — Plaid public token exchange has been replaced
// by the internal mock bank generator (useMockConnect).
// Kept as a stub to avoid breaking any residual imports.

export const useExchangePublicToken = () => {
  return {
    mutate: (_args: { publicToken: string }) => {},
    isPending: false,
    isSuccess: false,
    isError: false,
  };
};
