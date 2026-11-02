import {
  DownloadCta,
  Features,
  Hero,
  HowItWorks,
} from "@/components/landing";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";

export default function Home() {
  return (
    <main id="top" className="min-h-screen bg-background">
      <SiteHeader />
      <Hero />
      <HowItWorks />
      <Features />
      <DownloadCta />
      <SiteFooter />
    </main>
  );
}
