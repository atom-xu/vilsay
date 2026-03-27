import { Hero }          from "@/components/Hero";
import { FeatureGrid }   from "@/components/FeatureGrid";
import { HowItWorks }    from "@/components/HowItWorks";
import { ScenarioDemo }  from "@/components/ScenarioDemo";
import { DownloadSection } from "@/components/DownloadSection";

export default function HomePage() {
  return (
    <main>
      <Hero />
      <FeatureGrid />
      <HowItWorks />
      <ScenarioDemo />
      <DownloadSection />
    </main>
  );
}
