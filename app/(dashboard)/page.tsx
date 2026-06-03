import { DataGrid } from "@/components/data-grid";
import { DataCharts } from "@/components/data-charts";
import { AiInsightsCard } from "@/features/ai-insights/components/ai-insights-card";
import { AutoSeeder } from "@/components/auto-seeder";

export default function DashboardPage() {
  return (
    <div className="max-w-screen-2xl mx-auto w-full pb-10 -mt-24">
      {/* Invisible — fires POST /api/plaid/auto-seed on mount, seeds DB if empty */}
      {/* <AutoSeeder /> */}
      <AiInsightsCard />
      <DataGrid />
      <DataCharts />
    </div>
  );
};
