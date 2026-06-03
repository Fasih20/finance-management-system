// This hook is no longer used — Plaid link token creation has been replaced
// by the internal mock bank generator (useMockConnect).
// Kept as a stub to avoid breaking any residual imports.

export const useCreateLinkToken = () => {
  return {
    mutate: () => {},
    isPending: false,
    isSuccess: false,
    isError: false,
  };
};
