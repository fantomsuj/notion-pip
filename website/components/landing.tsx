import type { ReactNode } from "react";
import {
  ArrowBigUp,
  BatteryFull,
  BookOpen,
  Calendar,
  Check,
  CircleHelp,
  Command,
  Compass,
  Download,
  Ellipsis,
  Folder,
  Grid2x2,
  Layers,
  Mail,
  Minimize2,
  MousePointer2,
  Pin,
  Plus,
  RotateCw,
  Search,
  Trash2,
  Wifi,
} from "lucide-react";
import Image from "next/image";
import { downloadUrl } from "@/lib/site";

function TrafficLights({ className = "size-2.5" }: { className?: string }) {
  return (
    <div className="flex items-center gap-1.5">
      <span className={`${className} rounded-full bg-[#ff5f57]`} />
      <span className={`${className} rounded-full bg-[#febc2e]`} />
      <span className={`${className} rounded-full bg-[#28c840]`} />
    </div>
  );
}

export function Hero() {
  return (
    <section className="relative overflow-hidden">
      <div
        aria-hidden
        className="pointer-events-none absolute right-[-10%] top-[-20%] h-[70vh] w-[70vh] rounded-full opacity-70 blur-2xl"
        style={{
          background:
            "radial-gradient(closest-side, rgba(255,122,26,0.85), rgba(255,122,26,0.15) 60%, transparent 75%)",
        }}
      />
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 bottom-0 h-[62%]"
        style={{
          background:
            "linear-gradient(to top, var(--brand) 0%, var(--brand) 45%, color-mix(in oklab, var(--brand) 72%, transparent) 72%, transparent 100%)",
        }}
      />
      <div className="relative mx-auto grid max-w-7xl grid-cols-1 items-center gap-10 px-5 pb-20 pt-14 sm:px-8 lg:grid-cols-[minmax(0,0.9fr)_minmax(0,1.35fr)] lg:gap-12 lg:pb-24 lg:pt-12">
        <div className="page-stage page-stage-copy">
          <h1 className="max-w-[9.5ch] text-balance text-6xl font-extrabold leading-[1.04] tracking-tight text-foreground sm:text-7xl lg:text-[4.75rem]">
            Keep your page in sight
          </h1>
          <p className="mt-6 max-w-md text-pretty text-xl font-medium leading-relaxed text-white">
            Perch pins your most important Notion page above everything else, so
            you can think and write with ease.
          </p>
          <a
            href={downloadUrl}
            className="mt-8 inline-flex items-center gap-2 rounded-full bg-white px-5 py-3 text-base font-semibold text-black shadow-sm transition-transform hover:-translate-y-0.5"
          >
            <Download className="size-5" />
            Download for Mac
          </a>
        </div>
        <div className="page-stage page-stage-visual flex w-full justify-center lg:justify-end">
          <DesktopScene />
        </div>
      </div>
    </section>
  );
}

function DesktopScene() {
  return (
    <div className="relative aspect-[16/10] w-full max-w-[760px] select-none overflow-hidden rounded-[1.25rem] shadow-[0_40px_80px_-24px_rgba(20,30,80,0.55)] ring-1 ring-black/15 sm:rounded-[1.5rem]">
      <Image
        src="/desktop-wallpaper.jpg"
        alt=""
        fill
        sizes="(min-width: 1024px) 760px, (min-width: 640px) 80vw, 95vw"
        className="object-cover object-[center_28%]"
      />
      <div className="absolute inset-0 bg-black/10" />
      <div
        className="absolute inset-0"
        style={{
          background:
            "radial-gradient(90% 80% at 55% 42%, transparent 30%, rgba(0,0,0,0.42) 100%)",
        }}
      />
      <div className="absolute inset-x-0 top-0 z-20 flex items-center justify-between bg-black/20 px-3.5 py-[5px] text-[10px] font-medium text-white backdrop-blur-xl">
        <span className="flex items-center gap-3">
          <span className="flex items-center gap-1.5">
            <Image
              src="/perch-bird.png"
              alt=""
              width={64}
              height={64}
              sizes="36px"
              className="size-3.5 object-contain"
              aria-hidden
            />
            <span className="font-semibold text-white">Perch</span>
          </span>
          <span className="hidden items-center gap-3 sm:flex">
            <span>File</span>
            <span>Edit</span>
            <span>View</span>
            <span>Window</span>
            <span>Help</span>
          </span>
        </span>
        <span className="flex items-center gap-2.5">
          <Search className="size-3 opacity-90" />
          <Wifi className="size-3" />
          <BatteryFull className="size-3" />
          <span className="tabular-nums tracking-wide">Mon 9:41 AM</span>
        </span>
      </div>
      <div className="absolute left-[4%] top-[18%] w-[38%] max-w-[280px] rotate-[-1.5deg] rounded-xl border border-white/15 bg-brand/65 p-2.5 text-brand-foreground shadow-2xl backdrop-blur-md sm:rounded-2xl sm:p-3">
        <div className="mb-2 flex items-center gap-2 sm:mb-3">
          <TrafficLights />
          <span className="ml-1 text-[10px] font-medium text-white sm:text-[11px]">
            Messages
          </span>
        </div>
        <div className="space-y-2 sm:space-y-2.5">
          <MessageRow name="Alex" preview="Latest mockups look great" />
          <MessageRow name="Design Team" preview="Let's sync on the flows" />
          <MessageRow name="Jamie" preview="Pushed the updates" />
        </div>
      </div>
      <div className="absolute bottom-[16%] left-[8%] w-[34%] max-w-[250px] rotate-[1deg] rounded-xl border border-white/15 bg-brand/65 p-2.5 text-brand-foreground shadow-2xl backdrop-blur-md sm:rounded-2xl sm:p-3">
        <div className="mb-2 flex items-center gap-2 sm:mb-3">
          <TrafficLights />
          <span className="ml-1 text-[10px] font-medium text-white sm:text-[11px]">
            Calendar
          </span>
        </div>
        <p className="mb-1.5 text-[10px] font-semibold sm:mb-2 sm:text-[11px]">
          May 15, 2026
        </p>
        <div className="space-y-1.5 sm:space-y-2">
          <div className="rounded-md bg-brand-foreground/15 px-2 py-1 sm:py-1.5">
            <p className="text-[9px] font-medium sm:text-[10px]">Design sync</p>
            <p className="text-[8px] text-white sm:text-[9px]">
              10:00 – 11:00 AM
            </p>
          </div>
          <div className="rounded-md bg-highlight/80 px-2 py-1 text-highlight-foreground sm:py-1.5">
            <p className="text-[9px] font-medium sm:text-[10px]">Focus time</p>
            <p className="text-[8px] opacity-80 sm:text-[9px]">
              11:30 AM – 1:00 PM
            </p>
          </div>
        </div>
      </div>
      <div className="absolute right-[5%] top-[14%] w-[42%] max-w-[320px] rounded-xl border border-black/5 bg-card text-card-foreground shadow-[0_24px_50px_-12px_rgba(0,0,0,0.65)] sm:rounded-2xl">
        <div className="flex items-center justify-between border-b border-border/70 px-2.5 py-2 sm:px-3 sm:py-2.5">
          <div className="flex items-center gap-2">
            <TrafficLights />
          </div>
          <span className="text-[10px] font-medium text-white sm:text-[11px]">
            Acme OS Redesign
          </span>
          <span className="inline-flex size-4 items-center justify-center rounded-full text-white">
            <CircleHelp className="size-3.5" />
          </span>
        </div>
        <div className="p-3 sm:p-4">
          <h3 className="text-sm font-bold tracking-tight sm:text-base">
            Acme OS Redesign
          </h3>
          <p className="mt-2 text-[10px] font-semibold text-white sm:mt-3 sm:text-[11px]">
            Today
          </p>
          <ul className="mt-1.5 space-y-1 text-[11px] sm:mt-2 sm:space-y-1.5 sm:text-[12px]">
            <li className="flex items-center gap-2">
              <span className="inline-flex size-3.5 items-center justify-center rounded-[4px] bg-brand text-brand-foreground">
                <Check className="size-2.5" />
              </span>
              <span className="text-white line-through">Review user flows</span>
            </li>
            <li className="flex items-center gap-2">
              <span className="size-3.5 rounded-[4px] border border-border" />
              <span>Define success metrics</span>
            </li>
            <li className="flex items-center gap-2">
              <span className="size-3.5 rounded-[4px] border border-border" />
              <span>Share updates with team</span>
            </li>
          </ul>
          <p className="mt-2 text-[10px] font-semibold text-white sm:mt-3 sm:text-[11px]">
            Next
          </p>
          <ul className="mt-1.5 space-y-1 text-[11px] text-white sm:mt-2 sm:text-[12px]">
            <li className="flex items-center gap-2">
              <span className="size-1 rounded-full bg-foreground/50" />
              Prototype status bar
            </li>
            <li className="flex items-center gap-2">
              <span className="size-1 rounded-full bg-foreground/50" />
              Explore onboarding ideas
            </li>
          </ul>
          <p className="mt-3 text-[9px] text-white sm:mt-4 sm:text-[10px]">
            Edited just now
          </p>
        </div>
        <div className="absolute -right-2 -top-2 flex items-center gap-1 rounded-full bg-highlight px-2 py-1 text-[9px] font-bold uppercase tracking-wide text-highlight-foreground shadow-md">
          Pinned
        </div>
      </div>
      <div className="absolute bottom-[3.5%] left-1/2 z-20 flex -translate-x-1/2 items-center gap-1.5 rounded-2xl border border-white/20 bg-white/15 px-2.5 py-1.5 shadow-lg backdrop-blur-xl sm:gap-2 sm:px-3 sm:py-2">
        <DockIcon>
          <Grid2x2 className="size-3.5 sm:size-4" />
        </DockIcon>
        <DockIcon>
          <Calendar className="size-3.5 sm:size-4" />
        </DockIcon>
        <DockIcon>
          <Compass className="size-3.5 sm:size-4" />
        </DockIcon>
        <DockIcon>
          <Mail className="size-3.5 sm:size-4" />
        </DockIcon>
        <Image
          src="/perch-bird.png"
          alt=""
          width={64}
          height={64}
          sizes="36px"
          className="size-7 object-contain sm:size-8"
          aria-hidden
        />
        <DockIcon>
          <Folder className="size-3.5 sm:size-4" />
        </DockIcon>
        <DockIcon>
          <Trash2 className="size-3.5 sm:size-4" />
        </DockIcon>
      </div>
    </div>
  );
}

function DockIcon({ children }: { children: ReactNode }) {
  return (
    <span className="flex size-7 items-center justify-center rounded-[0.6rem] bg-brand-foreground/95 text-brand shadow-sm sm:size-8 sm:rounded-lg">
      {children}
    </span>
  );
}

function MessageRow({ name, preview }: { name: string; preview: string }) {
  return (
    <div className="flex items-center gap-2">
      <span className="size-5 shrink-0 rounded-full bg-brand-foreground/25 sm:size-6" />
      <div className="min-w-0">
        <p className="text-[10px] font-semibold leading-tight sm:text-[11px]">
          {name}
        </p>
        <p className="truncate text-[9px] text-white sm:text-[10px]">
          {preview}
        </p>
      </div>
    </div>
  );
}

export function HowItWorks() {
  const steps = [
    {
      title: "Choose",
      icon: MousePointer2,
      detail: "Pick any Notion page you want to keep visible while you work.",
    },
    {
      title: "Pin",
      icon: Pin,
      detail: "Perch pins it in a compact window above your other apps.",
    },
    {
      title: "Stay focused",
      icon: Layers,
      detail: "Read, reference, and write in your notetaker with ease.",
    },
  ];

  return (
    <section
      id="how-it-works"
      className="page-stage bg-brand text-brand-foreground"
    >
      <div className="mx-auto grid max-w-7xl grid-cols-1 gap-y-10 px-5 pb-24 pt-10 sm:px-8 md:grid-cols-3 md:gap-x-16 md:pb-28 md:pt-12 lg:gap-x-24">
        {steps.map((step, index) => (
          <div
            key={step.title}
            className={
              index < steps.length - 1
                ? "md:border-r md:border-dashed md:border-brand-foreground/25 md:pr-16 lg:pr-24"
                : undefined
            }
          >
            <div className="flex h-11 items-center justify-center gap-3">
              <h3 className="text-2xl font-bold tracking-tight">{step.title}</h3>
            </div>
            <div className="mt-5 flex justify-center">
              <step.icon className="size-12 text-white" />
            </div>
            <p className="mt-5 text-center text-sm leading-relaxed text-white">
              {step.detail}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}

export function Features() {
  return (
    <section id="features" className="page-stage bg-background text-white">
      <div className="mx-auto max-w-7xl px-5 py-20 sm:px-8">
        <h2 className="mb-12 text-5xl font-bold tracking-tight">Features</h2>
        <div className="grid grid-cols-1 items-start gap-6 pb-0 md:grid-cols-3 md:gap-14 md:pb-14">
          <div>
            <span className="font-mono text-4xl font-bold text-brand">01</span>
            <h3 className="mt-3 text-2xl font-bold tracking-tight">
              Always on top
            </h3>
            <p className="mt-2 max-w-sm text-sm leading-relaxed text-white">
              Your page stays visible while you work across apps, desktops, and
              spaces.
            </p>
            <div className="mt-6">
              <div className="relative h-24">
                <div className="absolute left-2 top-6 w-28 rounded-lg bg-brand/25 p-2">
                  <div className="h-1.5 w-10 rounded-full bg-brand/40" />
                  <div className="mt-1.5 h-1.5 w-16 rounded-full bg-brand/30" />
                </div>
                <div className="absolute left-10 top-0 w-36 rounded-lg bg-card p-2 shadow-lg">
                  <div className="flex gap-1">
                    <TrafficLights className="size-1.5" />
                  </div>
                  <div className="mt-2 h-1.5 w-20 rounded-full bg-foreground/15" />
                  <div className="mt-1.5 h-1.5 w-24 rounded-full bg-foreground/10" />
                </div>
              </div>
            </div>
          </div>
          <div>
            <span className="font-mono text-4xl font-bold text-brand">02</span>
            <h3 className="mt-3 text-2xl font-bold tracking-tight">
              Resize & reposition
            </h3>
            <p className="mt-2 max-w-sm text-sm leading-relaxed text-white">
              Place your Notion page wherever you need it.
            </p>
            <div className="mt-6">
              <div className="relative h-24">
                <div className="absolute inset-x-6 top-2 rounded-lg bg-brand p-3 text-brand-foreground shadow-lg">
                  <div className="h-1.5 w-14 rounded-full bg-brand-foreground/50" />
                  <div className="mt-2 h-1.5 w-24 rounded-full bg-brand-foreground/25" />
                  <div className="mt-1.5 h-1.5 w-20 rounded-full bg-brand-foreground/25" />
                </div>
                <span className="absolute left-4 top-0 size-2.5 rounded-full border-2 border-brand bg-card" />
                <span className="absolute right-4 top-0 size-2.5 rounded-full border-2 border-brand bg-card" />
                <span className="absolute bottom-0 left-4 size-2.5 rounded-full border-2 border-brand bg-card" />
                <span className="absolute bottom-0 right-4 size-2.5 rounded-full border-2 border-brand bg-card" />
              </div>
            </div>
          </div>
          <div>
            <span className="font-mono text-4xl font-bold text-brand">03</span>
            <h3 className="mt-3 text-2xl font-bold tracking-tight">
              Multiple spaces
            </h3>
            <p className="mt-2 text-sm leading-relaxed text-white">
              Keep a different pinned page per project and switch between them
              in a tap.
            </p>
            <div className="mt-6 space-y-2">
              <button
                type="button"
                aria-pressed="true"
                className="flex w-40 items-center gap-2 rounded-lg bg-brand px-3 py-2 text-sm font-medium text-brand-foreground"
              >
                <span className="size-2 rounded-full bg-highlight" />
                Work
              </button>
              <button
                type="button"
                aria-pressed="false"
                className="flex w-40 items-center gap-2 rounded-lg bg-card px-3 py-2 text-sm font-medium text-card-foreground"
              >
                <span className="size-2 rounded-full bg-muted-foreground/50" />
                Personal
              </button>
            </div>
          </div>
        </div>
        <div className="grid grid-cols-1 items-start gap-10 pt-10 md:grid-cols-3 md:gap-x-14 md:pt-14">
          <div className="flex flex-col">
            <span className="font-mono text-4xl font-bold text-brand">04</span>
            <h3 className="mt-3 text-2xl font-bold tracking-tight">
              Keyboard first
            </h3>
            <p className="mt-2 text-sm leading-relaxed text-white">
              Set your own shortcuts.
            </p>
            <div className="mt-6 flex items-center gap-2">
              <span className="flex h-10 min-w-10 items-center justify-center rounded-lg bg-secondary px-2 font-mono text-sm font-semibold text-white shadow-[0_3px_0_rgba(0,0,0,0.35)]">
                <Command className="size-4" />
              </span>
              <span className="flex h-10 min-w-10 items-center justify-center rounded-lg bg-secondary px-2 font-mono text-sm font-semibold text-white shadow-[0_3px_0_rgba(0,0,0,0.35)]">
                <ArrowBigUp className="size-4" />
              </span>
              <span className="flex h-10 min-w-10 items-center justify-center rounded-lg bg-secondary px-2 font-mono text-sm font-semibold text-white shadow-[0_3px_0_rgba(0,0,0,0.35)]">
                P
              </span>
            </div>
          </div>
          <div className="flex flex-col">
            <span className="font-mono text-4xl font-bold text-brand">05</span>
            <h3 className="mt-3 text-2xl font-bold tracking-tight">
              Functionality
            </h3>
            <p className="mt-2 text-sm leading-relaxed text-white">
              Use quick controls for maneuvering pages.
            </p>
            <div className="mt-6 flex w-fit items-center gap-2">
              <ChromeButton>
                <Plus className="size-5" />
              </ChromeButton>
              <ChromeButton>
                <BookOpen className="size-5" />
              </ChromeButton>
              <ChromeButton>
                <RotateCw className="size-5" />
              </ChromeButton>
              <ChromeButton>
                <span className="flex size-5 items-center justify-center rounded-sm border-2 border-current font-serif text-sm font-bold leading-none">
                  N
                </span>
              </ChromeButton>
              <ChromeButton>
                <Ellipsis className="size-5" />
              </ChromeButton>
              <ChromeButton>
                <Minimize2 className="size-5" />
              </ChromeButton>
            </div>
          </div>
          <div className="flex flex-col">
            <span className="font-mono text-4xl font-bold text-brand">06</span>
            <h3 className="mt-3 text-2xl font-bold tracking-tight">
              Native & lightweight
            </h3>
            <p className="mt-2 text-sm leading-relaxed text-white">
              Downloading for macOS takes a few minutes.
            </p>
            <span
              className="mt-6 flex size-10 items-center justify-center rounded-lg bg-secondary text-3xl leading-none text-white shadow-[0_3px_0_rgba(0,0,0,0.16),0_1px_8px_rgba(0,0,0,0.1)]"
              aria-hidden
            >
              
            </span>
          </div>
        </div>
      </div>
    </section>
  );
}

function ChromeButton({ children }: { children: ReactNode }) {
  return (
    <span className="flex size-10 items-center justify-center rounded-lg bg-secondary text-white shadow-[0_3px_0_rgba(0,0,0,0.16),0_1px_8px_rgba(0,0,0,0.1)]">
      {children}
    </span>
  );
}

export function DownloadCta() {
  return (
    <section
      id="download"
      className="page-stage relative isolate scroll-mt-20 overflow-hidden bg-ink text-brand-foreground"
    >
      <Image
        src="/light-band.jpg"
        alt=""
        fill
        sizes="100vw"
        className="-z-10 object-cover object-[center_55%]"
      />
      <div className="absolute inset-0 -z-10 bg-[radial-gradient(ellipse_at_center,transparent_0%,rgba(0,0,0,0.34)_48%,rgba(0,0,0,0.92)_100%),linear-gradient(to_right,var(--ink)_0%,rgba(0,0,0,0.62)_24%,rgba(0,0,0,0.24)_52%,var(--ink)_100%),linear-gradient(to_bottom,var(--ink)_0%,transparent_18%,transparent_78%,var(--ink)_100%)]" />
      <div className="mx-auto flex max-w-7xl flex-col items-start justify-between gap-8 px-5 py-16 sm:px-8 md:flex-row md:items-center md:py-28">
        <h2 className="text-balance text-6xl font-extrabold leading-[1.04] tracking-tight sm:text-7xl lg:text-[4.75rem]">
          Perched above
          <br />
          the busywork.
        </h2>
        <div className="flex flex-col items-start gap-3 md:items-end">
          <a
            href={downloadUrl}
            className="inline-flex items-center gap-3 rounded-full bg-white px-8 py-4 text-lg font-semibold text-black shadow-lg transition-transform hover:-translate-y-0.5"
          >
            <Download className="size-5" />
            Download for macOS
          </a>
        </div>
      </div>
    </section>
  );
}
