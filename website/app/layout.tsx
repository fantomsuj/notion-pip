import type { Metadata, Viewport } from "next";
import { Analytics } from "@vercel/analytics/next";
import { Geist_Mono, Inter } from "next/font/google";
import { PageIntro } from "@/components/page-intro";
import { siteUrl } from "@/lib/site";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

const geistMono = Geist_Mono({
  subsets: ["latin"],
  variable: "--font-geist-mono",
  display: "swap",
});

export const viewport: Viewport = {
  themeColor: "#171717",
  colorScheme: "dark",
};

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: "Perch: Your Notion page, always in view",
  description:
    "Perch pins your most important Notion page above everything else, so you can think and write with ease.",
  applicationName: "Perch",
  icons: {
    icon: "/perch-mark.png",
  },
  openGraph: {
    title: "Perch: Your Notion page, always in view",
    description:
      "Pin your most important Notion page in a compact window above your other apps.",
    url: siteUrl,
    siteName: "Perch",
    type: "website",
  },
  twitter: {
    card: "summary",
    title: "Perch: Your Notion page, always in view",
    description:
      "Pin your most important Notion page in a compact window above your other apps.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`dark ${inter.variable} ${geistMono.variable} bg-background`}
    >
      <body className="font-sans antialiased">
        <PageIntro />
        {children}
        <Analytics />
      </body>
    </html>
  );
}
