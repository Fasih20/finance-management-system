"use client";

import { CheckCircle2 } from "lucide-react";

import { useGetSubscription } from "@/features/subscriptions/api/use-get-subscription";
import { SubscriptionCheckout } from "@/features/subscriptions/components/subscription-checkout";

import { cn } from "@/lib/utils";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { Badge } from "@/components/ui/badge";

export const SettingsCard = () => {
  // Subscription data is still dynamic — only Plaid hooks have been removed.
  const {
    data: subscription,
    isLoading: isLoadingSubscription,
  } = useGetSubscription();

  return (
    <Card className="border-none drop-shadow-sm">
      <CardHeader>
        <CardTitle className="text-xl line-clamp-1">
          Settings
        </CardTitle>
      </CardHeader>
      <CardContent>
        {/* ── Bank Account ─────────────────────────────────────────── */}
        <Separator />
        <div className="flex flex-col gap-y-2 lg:flex-row items-center py-4">
          <p className="text-sm font-medium w-full lg:w-[16.5rem]">
            Bank account
          </p>
          <div className="w-full flex items-center justify-between">
            {/* Always show "connected" — data is seeded automatically on dashboard load */}
            <div className="flex items-center gap-x-2 text-sm text-emerald-600 font-medium">
              <CheckCircle2 className="size-4 shrink-0" />
              Bank account connected
            </div>
            <Badge
              variant="secondary"
              className="text-xs text-emerald-700 bg-emerald-50 border border-emerald-200 select-none"
            >
              Mock · Auto-seeded
            </Badge>
          </div>
        </div>

        {/* ── Subscription ─────────────────────────────────────────── */}
        <Separator />
        <div className="flex flex-col gap-y-2 lg:flex-row items-center py-4">
          <p className="text-sm font-medium w-full lg:w-[16.5rem]">
            Subscription
          </p>
          <div className="w-full flex items-center justify-between">
            <div className={cn(
              "text-sm truncate flex items-center",
              !subscription && "text-muted-foreground",
            )}>
              {isLoadingSubscription
                ? "Loading…"
                : subscription
                  ? `Subscription ${subscription.status}`
                  : "No subscription active"
              }
            </div>
            <SubscriptionCheckout />
          </div>
        </div>
      </CardContent>
    </Card>
  );
};
