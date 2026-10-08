// Voice JSON → OpenRouter paid model (Hinglish + JSON, cheaper than Gemini Flash-Lite).
// Camera → OpenRouter paid Gemini 2.5 Flash-Lite.
// Assistant Live chat (Roman Hinglish, text) → Qwen 3.7 Flash (fast + cheap + tool-calling).
// TTS → Sarvam Bulbul v3 (Hindi voice, streaming-capable).
// Secrets (never in the iOS app): OPENROUTER_API_KEY, SARVAM_API_KEY.
// Optional: OPENROUTER_VOICE_MODEL, OPENROUTER_VISION_MODEL, OPENROUTER_ASSISTANT_MODEL,
//   SARVAM_TTS_SPEAKER (default anushka), SARVAM_TTS_LANGUAGE (default hi-IN)

import { createClient } from "npm:@supabase/supabase-js@2";

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const VOICE_MODEL = Deno.env.get("OPENROUTER_VOICE_MODEL") ?? "google/gemma-3-27b-it";
const VISION_MODEL = Deno.env.get("OPENROUTER_VISION_MODEL") ?? "google/gemini-2.5-flash-lite";
const ASSISTANT_MODEL = Deno.env.get("OPENROUTER_ASSISTANT_MODEL") ?? "qwen/qwen3.7-flash";
const SARVAM_TTS_URL = "https://api.sarvam.ai/text-to-speech";
const SARVAM_TTS_SPEAKER = Deno.env.get("SARVAM_TTS_SPEAKER") ?? "priya";
const SARVAM_TTS_LANGUAGE = Deno.env.get("SARVAM_TTS_LANGUAGE") ?? "hi-IN";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors() });
  }

  try {
    const user = await requireUser(req);
    if (!user.ok) return user.response;

    const body = await req.json();
    const task = body.task as string | undefined;

    const admin = adminClient();
    if (task === "markPro") {
      const quota = await markPro(admin, user.user.id, String(body.jws ?? ""));
      return json({ ok: true, quota });
    }

    // Bulbul TTS does not consume an extra LLM turn; the Qwen assistant-chat
    // turn already counted. Skip consumeQuota entirely for TTS sentences.
    if (task === "bulbul-tts") {
      const audio = await sarvamBulbulTTS(body);
      return json({ ...audio });
    }

    const kind = task === "vision" ? "camera" : "voice";
    const quota = await consumeQuota(admin, user.user.id, kind);
    if (!quota.ok) {
      return json({ error: { message: quota.message, code: "quota_exceeded" } }, 402);
    }

    let payload: Record<string, unknown>;
    if (task === "vision") {
      payload = await openRouterVision(body);
    } else if (task === "assistant-chat") {
      payload = await openRouterAssistantChat(body);
    } else {
      payload = await openRouterVoice(body);
    }
    return json({ ...payload, quota: quota.snapshot });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return json({ error: { message } }, 500);
  }
});

async function requireUser(req: Request) {
  const auth = req.headers.get("Authorization") ?? "";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: auth } } },
  );
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) {
    return {
      ok: false as const,
      response: json({ error: { message: "Unauthorized" } }, 401),
    };
  }
  return { ok: true as const, user: data.user };
}

const FREE_LIMIT = 40;
const PRO_VOICE = 300;
const PRO_CAMERA = 100;
const BUNDLE_ID = "com.sourav.beasyyyy";
const PRO_PRODUCTS = new Set([
  "com.sourav.beasyyyy.pro.monthly",
  "com.sourav.beasyyyy.pro.yearly",
]);

function adminClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
}

function dayStamp() {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Kolkata",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function quotaSnapshot(row: Record<string, unknown>, pro: boolean) {
  const day = dayStamp();
  const voiceUsed = row.voice_month === day ? Number(row.voice_used ?? 0) : 0;
  const cameraUsed = row.camera_month === day ? Number(row.camera_used ?? 0) : 0;
  const freeUsed = Number(row.free_used ?? 0);
  return {
    isPro: pro,
    day,
    month: day,
    freeUsed,
    voiceUsed,
    cameraUsed,
    remainingFree: Math.max(0, FREE_LIMIT - freeUsed),
    remainingVoice: Math.max(0, PRO_VOICE - voiceUsed),
    remainingCamera: Math.max(0, PRO_CAMERA - cameraUsed),
  };
}

function isProActive(row: Record<string, unknown>) {
  if (!row.is_pro) return false;
  const exp = row.pro_expires_at as string | null;
  if (!exp) return true;
  return new Date(exp).getTime() > Date.now();
}

async function loadQuota(admin: ReturnType<typeof createClient>, userId: string) {
  const { data } = await admin.from("ai_quota").select("*").eq("user_id", userId).maybeSingle();
  return (data ?? {
    user_id: userId,
    free_used: 0,
    voice_month: dayStamp(),
    voice_used: 0,
    camera_month: dayStamp(),
    camera_used: 0,
    is_pro: false,
    pro_expires_at: null,
  }) as Record<string, unknown>;
}

async function saveQuota(admin: ReturnType<typeof createClient>, row: Record<string, unknown>) {
  await admin.from("ai_quota").upsert({
    user_id: row.user_id,
    free_used: row.free_used,
    voice_month: row.voice_month,
    voice_used: row.voice_used,
    camera_month: row.camera_month,
    camera_used: row.camera_used,
    is_pro: row.is_pro,
    pro_expires_at: row.pro_expires_at,
    updated_at: new Date().toISOString(),
  });
}

async function consumeQuota(
  admin: ReturnType<typeof createClient>,
  userId: string,
  kind: "voice" | "camera",
) {
  const row = await loadQuota(admin, userId);
  const day = dayStamp();
  if (row.voice_month !== day) {
    row.voice_month = day;
    row.voice_used = 0;
  }
  if (row.camera_month !== day) {
    row.camera_month = day;
    row.camera_used = 0;
  }
  const pro = isProActive(row);
  if (pro) {
    if (kind === "voice" && Number(row.voice_used) >= PRO_VOICE) {
      return { ok: false as const, message: "Pro voice scan cap reached today" };
    }
    if (kind === "camera" && Number(row.camera_used) >= PRO_CAMERA) {
      return { ok: false as const, message: "Pro photo scan cap reached today" };
    }
    if (kind === "voice") row.voice_used = Number(row.voice_used) + 1;
    else row.camera_used = Number(row.camera_used) + 1;
  } else {
    if (Number(row.free_used) >= FREE_LIMIT) {
      return { ok: false as const, message: "Free AI cap reached" };
    }
    row.free_used = Number(row.free_used) + 1;
  }
  await saveQuota(admin, row);
  return { ok: true as const, snapshot: quotaSnapshot(row, pro) };
}

function decodeJwsPayload(jws: string): Record<string, unknown> | null {
  const parts = jws.split(".");
  if (parts.length < 2) return null;
  try {
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const pad = "=".repeat((4 - (b64.length % 4)) % 4);
    return JSON.parse(atob(b64 + pad)) as Record<string, unknown>;
  } catch {
    return null;
  }
}

async function markPro(
  admin: ReturnType<typeof createClient>,
  userId: string,
  jws: string,
) {
  const payload = decodeJwsPayload(jws);
  const bundle = String(payload?.bundleId ?? payload?.bid ?? "");
  const product = String(payload?.productId ?? "");
  const expires = Number(payload?.expiresDate ?? 0);
  const row = await loadQuota(admin, userId);
  const valid =
    payload != null &&
    bundle === BUNDLE_ID &&
    PRO_PRODUCTS.has(product) &&
    (expires === 0 || expires > Date.now());
  row.is_pro = valid;
  row.pro_expires_at = valid && expires > 0 ? new Date(expires).toISOString() : null;
  await saveQuota(admin, row);
  return quotaSnapshot(row, isProActive(row));
}

function openRouterKey() {
  const key = Deno.env.get("OPENROUTER_API_KEY");
  if (!key) throw new Error("OPENROUTER_API_KEY is not set");
  return key;
}

function paidProvider() {
  return {
    allow_fallbacks: true,
    require_parameters: true,
  };
}

async function openRouterVoice(body: {
  systemPrompt?: string;
  userPrompt?: string;
  maxOutputTokens?: number;
}) {
  const systemPrompt = String(body.systemPrompt ?? "");
  const userPrompt = String(body.userPrompt ?? "");
  const maxTokens = Number(body.maxOutputTokens ?? 1024);

  const payload: Record<string, unknown> = {
    model: VOICE_MODEL,
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content: userPrompt },
    ],
    temperature: 0.1,
    max_tokens: maxTokens,
    response_format: { type: "json_object" },
    provider: paidProvider(),
  };

  let result = await openRouterChat(payload);
  if (!result.ok && result.retryWithoutJson) {
    delete payload.response_format;
    result = await openRouterChat(payload);
  }
  if (!result.ok) throw new Error(result.error);
  return geminiShaped(result.text);
}

/// Assistant Live chat: Roman Hinglish/English text reply (no JSON mode).
/// Body: { messages: [{role, content}], maxOutputTokens?, temperature? }
/// Supports: plain text answer OR a single tool line `SQL: SELECT ...` for shop queries.
async function openRouterAssistantChat(body: {
  messages?: Array<{ role?: string; content?: string }>;
  systemPrompt?: string;
  userPrompt?: string;
  maxOutputTokens?: number;
  temperature?: number;
}) {
  const maxTokens = Math.min(Number(body.maxOutputTokens ?? 400), 1024);
  const temperature = Number(body.temperature ?? 0.1);
  let messages: Array<Record<string, string>>;
  if (Array.isArray(body.messages) && body.messages.length > 0) {
    messages = body.messages
      .filter((m) => m && typeof m.content === "string")
      .map((m) => ({ role: m.role === "assistant" ? "assistant" : "user", content: String(m.content).slice(0, 4000) }))
      .slice(-21);
  } else {
    messages = [
      { role: "system", content: String(body.systemPrompt ?? "You are B-easy shop assistant. Reply in Roman Hinglish only, no Devanagari.") },
      { role: "user", content: String(body.userPrompt ?? "").slice(0, 4000) },
    ];
  }

  // Primary: Qwen (cheap + fast). Fallback: Gemini Flash-Lite (proven) —
  // some Qwen routes return empty content under load; never fail the turn.
  const models = [ASSISTANT_MODEL, VISION_MODEL];
  let lastError = "unknown";
  for (const model of models) {
    const payload: Record<string, unknown> = {
      model,
      messages,
      temperature,
      max_tokens: maxTokens,
      provider: paidProvider(),
    };
    const result = await openRouterChat(payload);
    if (result.ok) {
      if (model !== ASSISTANT_MODEL) console.log(`assistant-chat fallback used: ${model}`);
      return geminiShaped(result.text);
    }
    lastError = result.error;
    console.log(`assistant-chat ${model} failed: ${result.error}`);
  }
  throw new Error(lastError);
}

/// Sarvam Bulbul v3 TTS. Body: { text, speaker?, language?, pace? }
/// Returns { audioBase64, format } — text is transliterated server-side hint:
/// Bulbul speaks native script best, so Roman Hinglish is sent as-is (Bulbul
/// handles romanized Hindi) with hi-IN target language.
async function sarvamBulbulTTS(body: {
  text?: string;
  speaker?: string;
  language?: string;
  pace?: number;
}): Promise<Record<string, unknown>> {
  const key = Deno.env.get("SARVAM_API_KEY");
  if (!key) throw new Error("SARVAM_API_KEY is not set (add via supabase secrets set)");
  const text = String(body.text ?? "").trim().slice(0, 2500);
  if (!text) throw new Error("bulbul-tts requires text");
  const speaker = String(body.speaker ?? SARVAM_TTS_SPEAKER);
  const language_code: string = String(body.language ?? SARVAM_TTS_LANGUAGE);
  const pace = Math.min(Math.max(Number(body.pace ?? 1.0), 0.5), 2.0);

  const res = await fetch(SARVAM_TTS_URL, {
    method: "POST",
    headers: {
      "api-subscription-key": key,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      text,
      language_code,
      speaker,
      pace,
      model: "bulbul:v3",
    }),
  });
  const raw = await res.text();
  if (!res.ok) throw new Error(`Sarvam TTS HTTP ${res.status}: ${raw.slice(0, 300)}`);
  let parsed: Record<string, unknown> = {};
  try {
    parsed = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    throw new Error("Sarvam TTS returned non-JSON response");
  }
  // Sarvam returns { audios: [base64], ... } — normalize to audioBase64.
  const audios = parsed.audios as Array<string> | undefined;
  const audioBase64 = (audios && audios[0]) ?? (parsed.audio as string | undefined) ?? "";
  if (!audioBase64) throw new Error("Sarvam TTS returned empty audio");
  return { audioBase64, format: "wav", speaker, language: language_code };
}

async function openRouterVision(body: {
  systemPrompt?: string;
  userPrompt?: string;
  image?: { mime_type?: string; data?: string };
  maxOutputTokens?: number;
}) {
  const systemPrompt = String(body.systemPrompt ?? "");
  const userPrompt = String(body.userPrompt ?? "Extract data from this image.");
  const image = body.image;
  if (!image?.data) throw new Error("vision task requires image.data");

  const mime = image.mime_type ?? "image/jpeg";
  const payload: Record<string, unknown> = {
    model: VISION_MODEL,
    messages: [
      { role: "system", content: systemPrompt },
      {
        role: "user",
        content: [
          { type: "image_url", image_url: { url: `data:${mime};base64,${image.data}` } },
          { type: "text", text: userPrompt },
        ],
      },
    ],
    temperature: 0.1,
    max_tokens: Number(body.maxOutputTokens ?? 2048),
    response_format: { type: "json_object" },
    reasoning: { effort: "none", exclude: true },
    provider: paidProvider(),
  };

  let result = await openRouterChat(payload);
  if (!result.ok && result.retryWithoutJson) {
    delete payload.response_format;
    result = await openRouterChat(payload);
  }
  if (!result.ok) throw new Error(result.error);
  return geminiShaped(result.text);
}

async function openRouterChat(
  payload: Record<string, unknown>,
): Promise<{ ok: true; text: string } | { ok: false; error: string; retryWithoutJson: boolean }> {
  const res = await fetch(OPENROUTER_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openRouterKey()}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://beasy.app",
      "X-Title": "B-easy",
    },
    body: JSON.stringify(payload),
  });
  const raw = await res.text();
  let parsed: Record<string, unknown> = {};
  try {
    parsed = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return {
      ok: false,
      error: `OpenRouter HTTP ${res.status}: ${raw.slice(0, 300)}`,
      retryWithoutJson: false,
    };
  }

  if (!res.ok) {
    const err = JSON.stringify(parsed.error ?? parsed).slice(0, 400);
    const retryWithoutJson = /response_format|json_object|json mode/i.test(err);
    return { ok: false, error: `OpenRouter HTTP ${res.status}: ${err}`, retryWithoutJson };
  }

  const choices = parsed.choices as Array<{ message?: { content?: unknown } }> | undefined;
  const content = choices?.[0]?.message?.content;
  const text = typeof content === "string"
    ? content
    : Array.isArray(content)
    ? content.map((part) => {
      if (typeof part === "string") return part;
      if (part && typeof part === "object" && "text" in part) return String((part as { text?: string }).text ?? "");
      return "";
    }).join("")
    : "";
  if (!text) {
    return { ok: false, error: "OpenRouter returned empty content", retryWithoutJson: false };
  }
  return { ok: true, text };
}

function geminiShaped(text: string) {
  return {
    candidates: [{ content: { parts: [{ text }] } }],
  };
}

function cors() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...cors(), "Content-Type": "application/json" },
  });
}
