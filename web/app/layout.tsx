import type { Metadata, Viewport } from "next";
import "./globals.css";
import { ServiceWorker } from "./service-worker";

export const metadata: Metadata = {
  title: "Elektramat Kabelmeter",
  description: "Bereken hoeveel kabel je nodig hebt en wat het kost, en zet het in je winkelmand.",
  appleWebApp: { capable: true, title: "Kabelmeter", statusBarStyle: "default" },
};

export const viewport: Viewport = {
  themeColor: "#196cae",
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="nl">
      <body>
        {children}
        <ServiceWorker />
      </body>
    </html>
  );
}
