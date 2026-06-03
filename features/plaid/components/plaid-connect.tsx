"use client";

import { Building2, Loader2 } from "lucide-react";
import { useMockConnect } from "@/features/plaid/api/use-mock-connect";
import { Button } from "@/components/ui/button";

export const PlaidConnect = () => {
  const mockConnect = useMockConnect();

  const onClick = () => {
    mockConnect.mutate();
  };

  return (
    <Button
      onClick={onClick}
      disabled={mockConnect.isPending}
      size="sm"
      variant="ghost"
    >
      {mockConnect.isPending ? (
        <>
          <Loader2 className="mr-2 size-4 animate-spin" />
          Connecting…
        </>
      ) : (
        <>
          <Building2 className="mr-2 size-4" />
          Connect
        </>
      )}
    </Button>
  );
};
