import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

type Role = "student" | "teacher" | "admin" | "district_admin" | "employer";

type Membership = {
  org_id: string;
  role: Role;
};

type Org = {
  id: string;
  name: string;
};

export default async function DashboardPage() {
  const supabase = await createClient();

  // 1) Logged in?
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData?.user) redirect("/login");
  const user = userData.user;

  // 2) RLS-protected memberships
  const { data: memberships, error: mErr } = await supabase
    .from("memberships")
    .select("org_id, role")
    .order("created_at", { ascending: true });

  if (mErr) {
    return (
      <main className="p-6">
        <h1 className="text-2xl font-semibold">Dashboard</h1>
        <p className="mt-2 text-sm">Logged in as: {user.email}</p>
        <pre className="mt-4 whitespace-pre-wrap border p-3 text-sm">
          {JSON.stringify(mErr, null, 2)}
        </pre>
      </main>
    );
  }

  const ms = (memberships ?? []) as Membership[];
  const orgIds = Array.from(new Set(ms.map((x) => x.org_id)));

  // 3) Fetch orgs by id (also RLS-protected)
  const { data: orgs, error: oErr } = await supabase
    .from("orgs")
    .select("id, name")
    .in("id", orgIds);

  if (oErr) {
    return (
      <main className="p-6">
        <h1 className="text-2xl font-semibold">Dashboard</h1>
        <p className="mt-2 text-sm">Logged in as: {user.email}</p>
        <pre className="mt-4 whitespace-pre-wrap border p-3 text-sm">
          {JSON.stringify(oErr, null, 2)}
        </pre>
      </main>
    );
  }

  const orgMap = new Map((orgs ?? []).map((o) => [o.id, o] as const));

  const rows = ms.map((m) => ({
    role: m.role,
    org: orgMap.get(m.org_id) ?? null
  }));

  return (
    <main className="p-6 max-w-2xl mx-auto">
      <h1 className="text-2xl font-semibold">Dashboard</h1>
      <p className="mt-2 text-sm">
        Logged in as: {user.email} ·{" "}
        <a className="underline" href="/logout">
          Logout
        </a>
      </p>

      <section className="mt-6">
        <h2 className="text-lg font-semibold">Your org memberships</h2>

        {rows.length === 0 ? (
          <p className="mt-2 text-sm">
            No memberships found (either you’re not in an org, or RLS is blocking access).
          </p>
        ) : (
          <ul className="mt-3 space-y-2">
            {rows.map((r, idx) => (
              <li key={idx} className="border rounded p-3">
                <div className="font-medium">{r.org?.name ?? "(missing org)"}</div>
                <div className="text-sm opacity-80">Role: {r.role}</div>
                <div className="text-xs opacity-60">Org ID: {r.org?.id ?? "(unknown)"}</div>
              </li>
            ))}
          </ul>
        )}
      </section>
    </main>
  );
}
