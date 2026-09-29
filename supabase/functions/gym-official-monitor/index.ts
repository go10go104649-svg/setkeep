import { createMonitorHandler } from './handler.mjs';

// Service credential remains inside Edge runtime. Callers get no arbitrary URL API.
const base = Deno.env.get('SUPABASE_URL')!;
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
Deno.serve(createMonitorHandler({
  rpc: async (name: string, args: unknown) => {
    const response = await fetch(`${base}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: key, Authorization: `Bearer ${key}` },
      body: JSON.stringify(args),
    });
    if (!response.ok) throw new Error(`DB RPC failed: ${response.status}`);
    return await response.json();
  },
  resolve: async (host: string) => {
    const results = await Promise.allSettled([
      Deno.resolveDns(host, 'A'), Deno.resolveDns(host, 'AAAA'),
    ]);
    return results.flatMap(r => r.status === 'fulfilled' ? r.value : []);
  },
}));
