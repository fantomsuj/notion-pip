import Image from "next/image";
import { Download } from "lucide-react";
import { downloadUrl } from "@/lib/site";

export function SiteHeader() {
  return (
    <header className="page-stage sticky top-0 z-50 bg-background/90 backdrop-blur-md">
      <div className="mx-auto flex max-w-7xl items-center justify-between gap-6 px-5 py-5 sm:px-8">
        <a
          href="#top"
          className="flex items-center gap-3 text-foreground"
          aria-label="Perch home"
        >
          <Image
            src="/perch-bird.png"
            alt=""
            width={64}
            height={64}
            sizes="36px"
            className="-ml-2 size-9 shrink-0 translate-y-[1px] object-contain"
            aria-hidden
          />
          <span className="text-xl font-extrabold leading-none tracking-tight">
            Perch
          </span>
        </a>
        <a
          href={downloadUrl}
          className="inline-flex size-11 items-center justify-center rounded-full bg-white text-black shadow-sm transition-transform hover:-translate-y-0.5"
          aria-label="Download for Mac"
        >
          <Download className="size-5" />
        </a>
      </div>
    </header>
  );
}
