import Image from "next/image";
import { GitFork } from "lucide-react";
import { downloadUrl, githubUrl } from "@/lib/site";

export function SiteFooter() {
  return (
    <footer className="page-stage bg-ink text-ink-foreground">
      <div className="mx-auto grid max-w-7xl gap-10 px-5 py-14 sm:px-8 md:grid-cols-3">
        <div>
          <div className="flex items-center gap-2.5">
            <Image
              src="/perch-bird.png"
              alt=""
              width={64}
              height={64}
              sizes="36px"
              className="-ml-1.5 size-8 -translate-y-[1px] object-contain"
              aria-hidden
            />
            <span className="text-sm font-semibold leading-none">Perch</span>
          </div>
          <p className="mt-3 text-sm text-ink-foreground/60">
            Your Notion page,
            <br />
            always in sight.
          </p>
          <a
            href={githubUrl}
            className="mt-4 inline-flex items-center gap-1.5 text-sm text-ink-foreground/60 transition-colors hover:text-ink-foreground"
          >
            <GitFork className="size-4" />
            Open sourced on GitHub
          </a>
        </div>
        <nav>
          <p className="text-sm font-semibold">Product</p>
          <ul className="mt-3 space-y-2">
            <li>
              <a
                href={downloadUrl}
                className="text-sm text-ink-foreground/60 transition-colors hover:text-ink-foreground"
              >
                Download
              </a>
            </li>
          </ul>
        </nav>
        <div className="md:text-right">
          <p className="text-sm font-semibold">Made with focus in mind.</p>
          <p className="mt-3 text-sm text-ink-foreground/60">
            Built to make writing easier.
          </p>
        </div>
      </div>
      <div className="border-t border-ink-foreground/10">
        <div className="mx-auto max-w-7xl px-5 py-5 sm:px-8">
          <p className="text-xs text-ink-foreground/50">
            © {new Date().getFullYear()} Perch. All rights reserved.
          </p>
        </div>
      </div>
    </footer>
  );
}
