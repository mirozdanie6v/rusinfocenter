const VENUE_CONTEXT = `
You are the AI concierge for The Cloud, a rooftop bar in Nha Trang, Vietnam.
Known facts:
- Address: 163 Nguyễn Thiện Thuật, Nha Trang.
- Public hours shown in this demo: 12:00–02:00.
- Booking deposit shown in this demo: 500,000 VND.
- A booking request is not final until a manager confirms it.
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
- If live availability or a fact is unknown, say it needs manager confirmation and suggest booking/contacting the manager.
- You may recommend a position when the user's needs make one appropriate.
- Do not claim that a reservation has been created unless the user actually completes the booking flow in the app.
`;

function languageInstruction(lang) {
  if (lang === "vi") return "Reply in Vietnamese.";
  if (lang === "en") return "Reply in English.";
  return "Reply in Russian.";
}

function recommendZone(text = "") {
  const q = text.toLowerCase();
  if (/shisha|hookah|кальян|shisha|thuốc shisha/.test(q)) return "shisha";
  if (/sunset|закат|golden hour|hoàng hôn/.test(q)) return "sunset";
  if (/group|company|birthday|компан|день рождения|nhóm|sinh nhật|vip|private|приват/.test(q)) return "vip";
  if (/bar|cocktail|music|music|бар|коктейл|музык|âm nhạc|cocktail/.test(q)) return "bar";
  if (/view|вид|панорам|photo|фото|ảnh|tầm nhìn|rooftop/.test(q)) return "roof";
  return null;
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

        const messages = [
          { role: "system", content: VENUE_CONTEXT + "\n" + languageInstruction(lang) },
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

        const reply = String(result?.response || "").trim();
        if (!reply) throw new Error("Empty AI response");

        return Response.json({
          reply,
          recommendedZone: recommendZone(question + " " + reply)
        });
      } catch (error) {
        console.error("AI concierge error", error);
        return Response.json({ error: "AI temporarily unavailable" }, { status: 500 });
      }
    }

    return env.ASSETS.fetch(request);
  }
};