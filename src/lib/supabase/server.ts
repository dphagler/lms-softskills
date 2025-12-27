import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";

export async function createClient() {
  const cookieStore = await cookies(); // cookies() is async in newer Next.js :contentReference[oaicite:4]{index=4}

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        // Server Components can’t reliably set cookies; the Proxy handles refresh + set.
        setAll() {}
      }
    }
  );
}
