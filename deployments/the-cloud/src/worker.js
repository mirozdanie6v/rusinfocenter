const VENUE_CONTEXT = `
You are the AI concierge for The Cloud, a rooftop bar in Nha Trang, Vietnam.
Known facts:
- Address: 163 Nguyễn Thiện Thuật, Nha Trang.
- Public hours shown in this demo: 12:00–02:00.
- Booking deposit shown in this demo: 500,000 VND.
- Customers start and complete the booking request inside the app using the Reserve/Booking flow.
- The in-app flow collects date, time, number of guests, position, table, customer details and deposit/payment step.
- After the customer submits the request in the app, a manager may confirm the final booking status.
- Contact may come from the Mini App source such as Telegram or WhatsApp.
- Positions:
  1. Rooftop View — open air, panoramic city view, good general choice.
  2. Sunset Line — best for sunset/golden-hour views, especially around 18:00–19:30.
  3. Shisha Lounge — softer seating, relaxed atmosphere, good for shisha and long conversations.
  4. Bar / Social — closer to the bar, livelier atmosphere, cocktails and socialising.
  5. Group / VIP — more privacy and space for groups and special occasions.
Rules:
- Answer only as The Cloud concierge.
- Use the user's selected language: Russian (ru), English (en), or Vietnamese (vi).
- Be concise, helpful and natural, usually 1–4 short paragraphs.
- Use conversation history when it is relevant.
- Never invent availability, menu items, prices, events, discounts, table numbers, payment success, or confirmed reservations.
- The app is the primary booking channel. If the user asks how to book, reserve, get a table, or continue a reservation, tell them to use the in-app Reserve/Booking flow.
- Never say that contacting a manager is the only way, required first step, or normal way to make a booking.
- If live availability is unknown, explain that the customer can still submit a booking request in the app and final availability will be confirmed after submission.
- Mention contacting a manager only for exceptional requests, facts not present in the known data, or when the user explicitly asks for a human.
- If you need human help because the requested information is not in the known facts, end the reply with exactly [MANAGER_HELP]. Do not use this marker for normal booking or availability questions.
- You may recommend positions when the user's needs make them appropriate. Recommend only genuinely suitable positions, never all positions by default, and never more than two in one answer.
- When recommending a position, use its exact name: Rooftop View, Sunset Line, Shisha Lounge, Bar / Social, or Group / VIP.
- The UI will provide booking buttons for any exact position names you recommend, so do not tell the user to manually search for the position.
- Do not claim that a reservation has been created unless the user actually completes the booking flow in the app.
`;

function isBookingIntent(text = "") {
  return /book|booking|reserve|reservation|table|заброн|брон|стол|đặt bàn|đặt chỗ|bàn/.test(text.toLowerCase());
}

function languageInstruction(lang) {
  if (lang === "vi") return "Reply in Vietnamese.";
  if (lang === "en") return "Reply in English.";
  return "Reply in Russian.";
}

function recommendZones(text = "") {
  const q = text.toLowerCase();
  const out = [];
  const add = id => { if (!out.includes(id) && out.length < 2) out.push(id); };

  // Prefer exact zone names from the AI reply.
  if (q.includes("rooftop view")) add("roof");
  if (q.includes("sunset line")) add("sunset");
  if (q.includes("shisha lounge")) add("shisha");
  if (q.includes("bar / social") || q.includes("bar/social")) add("bar");
  if (q.includes("group / vip") || q.includes("group/vip")) add("vip");

  // Fallback from the user's intent when exact names were not emitted.
  if (out.length < 2 && /sunset|закат|golden hour|hoàng hôn/.test(q)) add("sunset");
  if (out.length < 2 && /shisha|hookah|кальян|thuốc shisha/.test(q)) add("shisha");
  if (out.length < 2 && /group|company|birthday|компан|день рождения|nhóm|sinh nhật|vip|private|приват/.test(q)) add("vip");
  if (out.length < 2 && /bar|cocktail|music|бар|коктейл|музык|âm nhạc/.test(q)) add("bar");
  if (out.length < 2 && /view|вид|панорам|photo|фото|ảnh|tầm nhìn|rooftop/.test(q)) add("roof");

  return out.slice(0, 2);
}

function extractActions(rawReply, question) {
  const needsManager = rawReply.includes("[MANAGER_HELP]");
  const reply = rawReply.replace(/\s*\[MANAGER_HELP\]\s*/g, " ").trim();
  return {
    reply,
    needsManager,
    recommendedZones: recommendZones(question + "\n" + reply)
  };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/ai/health") {
      return Response.json({ ok: true, ai: Boolean(env.AI) });
    }

    if (url.pathname === "/api/ai") {
      if (request.method !== "POST") {
        return Response.json({ error: "Method not allowed" }, { status: 405 });
      }

      try {
        const body = await request.json();
        const question = String(body?.question || "").trim().slice(0, 1200);
        const lang = ["ru", "en", "vi"].includes(body?.lang) ? body.lang : "ru";
        const history = Array.isArray(body?.history) ? body.history.slice(-8) : [];

        if (!question) {
          return Response.json({ error: "Empty question" }, { status: 400 });
        }

        const bookingIntent = isBookingIntent(question);
        const bookingRule = bookingIntent
          ? "\nThe user is asking about booking. Direct them to the in-app Reserve/Booking flow. Do not direct them to a manager unless they explicitly request human help or have an exceptional request the app cannot represent."
          : "";

        const messages = [
          { role: "system", content: VENUE_CONTEXT + "\n" + languageInstruction(lang) + bookingRule },
          ...history
            .filter(m => m && ["user", "assistant"].includes(m.role))
            .map(m => ({ role: m.role, content: String(m.content || "").slice(0, 1200) })),
          { role: "user", content: question }
        ];

        const result = await env.AI.run("@cf/meta/llama-3.1-8b-instruct-fast", {
          messages,
          max_tokens: 420,
          temperature: 0.35
        });

        const rawReply = String(result?.response || "").trim();
        if (!rawReply) throw new Error("Empty AI response");

        const actions = extractActions(rawReply, question);
        return Response.json(actions);
      } catch (error) {
        console.error("AI concierge error", error);
        return Response.json({ error: "AI temporarily unavailable" }, { status: 500 });
      }
    }

    return env.ASSETS.fetch(request);
  }
};