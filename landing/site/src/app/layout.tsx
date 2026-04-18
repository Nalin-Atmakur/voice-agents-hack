import type { Metadata } from 'next';
import { DM_Sans, JetBrains_Mono } from 'next/font/google';
import './globals.css';

const dmSans = DM_Sans({
  subsets: ['latin'],
  variable: '--font-dm-sans',
  display: 'swap',
  weight: ['300', '400', '500', '600', '700', '800'],
});

const jetBrainsMono = JetBrains_Mono({
  subsets: ['latin'],
  variable: '--font-jetbrains-mono',
  display: 'swap',
  weight: ['400', '500', '600'],
});

export const metadata: Metadata = {
  title: 'TacNet — Voice. Mesh. Offline.',
  description:
    'A decentralised, offline-first tactical communication network that runs Gemma 4 on-device and compacts transmissions up a command tree. Zero servers. Zero cloud.',
  metadataBase: new URL('https://tacnet.example'),
  openGraph: {
    title: 'TacNet — Voice. Mesh. Offline.',
    description:
      'A decentralised, offline-first tactical communication network that runs Gemma 4 on-device and compacts transmissions up a command tree.',
    type: 'website',
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      className={`${dmSans.variable} ${jetBrainsMono.variable}`}
    >
      <body className="relative min-h-screen antialiased">
        {/* Grain overlay — pinned, non-interactive */}
        <div
          aria-hidden
          className="bg-noise pointer-events-none fixed inset-0 z-50"
        />
        {children}
      </body>
    </html>
  );
}
