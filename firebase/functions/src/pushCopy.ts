/**
 * Partner-push copy in every Missuo language.
 * Recipient locale comes from users/{id}.appLanguage (synced by the app).
 */

export type MissuoLang = "en" | "fr" | "de" | "ko" | "pt" | "es";

export function normalizeLang(raw: string | undefined): MissuoLang {
  const code = (raw ?? "en").slice(0, 2).toLowerCase();
  if (code === "fr" || code === "de" || code === "ko" || code === "pt" || code === "es") {
    return code;
  }
  return "en";
}

type Template = Record<MissuoLang, string>;

const answersUnlockedTitle: Template = {
  en: "Answers unlocked 🔓",
  fr: "Réponses débloquées 🔓",
  de: "Antworten freigeschaltet 🔓",
  ko: "답이 공개됐어요 🔓",
  pt: "Respostas desbloqueadas 🔓",
  es: "Respuestas desbloqueadas 🔓",
};

const answersUnlockedBody: Template = {
  en: "You both answered — read them together.",
  fr: "Vous avez tous les deux répondu — lisez-les ensemble.",
  de: "Ihr habt beide geantwortet — lest sie zusammen.",
  ko: "둘 다 답했어요 — 함께 읽어보세요.",
  pt: "Responderam os dois — leiam juntos.",
  es: "Los dos habéis respondido — leedlas juntos.",
};

const partnerAnsweredTitle: Template = {
  en: "Your partner answered 💭",
  fr: "Ton partenaire a répondu 💭",
  de: "Dein Partner hat geantwortet 💭",
  ko: "파트너가 답했어요 💭",
  pt: "O teu par respondeu 💭",
  es: "Tu pareja ha respondido 💭",
};

const partnerAnsweredBody: Template = {
  en: "Answer today's question to unlock what they wrote.",
  fr: "Réponds à la question du jour pour découvrir ce qu'il/elle a écrit.",
  de: "Beantworte die heutige Frage, um zu sehen, was dein Partner geschrieben hat.",
  ko: "오늘의 질문에 답하면 상대의 답을 볼 수 있어요.",
  pt: "Responde à pergunta de hoje para ver o que escreveram.",
  es: "Responde la pregunta de hoy para ver lo que escribió.",
};

const moodTitle: Template = {
  en: "Mood update 💗",
  fr: "Humeur mise à jour 💗",
  de: "Stimmungs-Update 💗",
  ko: "기분 업데이트 💗",
  pt: "Atualização de humor 💗",
  es: "Actualización de ánimo 💗",
};

const moodBody: Template = {
  en: "Your partner just checked in. See how they're feeling.",
  fr: "Ton partenaire vient de se connecter. Vois comment il/elle se sent.",
  de: "Dein Partner hat gerade eingecheckt. Sieh, wie es ihm/ihr geht.",
  ko: "파트너가 방금 체크인했어요. 기분을 확인해 보세요.",
  pt: "O teu par acabou de fazer check-in. Vê como se sente.",
  es: "Tu pareja acaba de registrarse. Mira cómo se siente.",
};

export function missYouPush(name: string, lang: MissuoLang): { title: string; body: string } {
  const t: Record<MissuoLang, { title: string; body: string }> = {
    en: { title: `${name} misses you 🥺`, body: "Tap to send one back." },
    fr: { title: `${name} a besoin de toi 🥺`, body: "Appuie pour lui envoyer un signe." },
    de: { title: `${name} vermisst dich 🥺`, body: "Tippe, um eins zurückzuschicken." },
    ko: { title: `${name}님이 보고 싶어해요 🥺`, body: "탭해서 답장을 보내세요." },
    pt: { title: `${name} sente a tua falta 🥺`, body: "Toca para responder." },
    es: { title: `${name} te echa de menos 🥺`, body: "Toca para devolverle el gesto." },
  };
  return t[lang];
}

export function heartPush(name: string, lang: MissuoLang): { title: string; body: string } {
  const t: Record<MissuoLang, { title: string; body: string }> = {
    en: { title: `${name} dropped a heart in your love jar ❤️`, body: "They're thinking of you right now." },
    fr: { title: `${name} a laissé un cœur dans votre bocal ❤️`, body: "Il/elle pense à toi en ce moment." },
    de: { title: `${name} hat ein Herz in euer Glas gelegt ❤️`, body: "Du bist gerade in seinen/ihren Gedanken." },
    ko: { title: `${name}님이 사랑 병에 하트를 넣었어요 ❤️`, body: "지금 당신을 생각하고 있어요." },
    pt: { title: `${name} deixou um coração no vosso frasco ❤️`, body: "Está a pensar em ti agora." },
    es: { title: `${name} dejó un corazón en vuestro tarro ❤️`, body: "Está pensando en ti ahora mismo." },
  };
  return t[lang];
}

export function hugPush(name: string, lang: MissuoLang): { title: string; body: string } {
  const t: Record<MissuoLang, { title: string; body: string }> = {
    en: { title: `${name} sent you a hug 🤗`, body: "Wrap it around yourself." },
    fr: { title: `${name} t'a envoyé un câlin 🤗`, body: "Garde-le contre toi." },
    de: { title: `${name} hat dir eine Umarmung geschickt 🤗`, body: "Nimm sie in Empfang." },
    ko: { title: `${name}님이 포옹을 보냈어요 🤗`, body: "마음에 품어보세요." },
    pt: { title: `${name} enviou-te um abraço 🤗`, body: "Acolhe-o com carinho." },
    es: { title: `${name} te envió un abrazo 🤗`, body: "Abrázalo con el corazón." },
  };
  return t[lang];
}

export function widgetNotePush(name: string, lang: MissuoLang): { title: string; body: string } {
  const t: Record<MissuoLang, { title: string; body: string }> = {
    en: { title: `${name} left a note on your widget 💌`, body: "It's syncing to your home screen now." },
    fr: { title: `${name} a laissé un mot sur ton widget 💌`, body: "Il arrive sur ton écran d'accueil." },
    de: { title: `${name} hat eine Notiz auf dein Widget gelegt 💌`, body: "Sie wird gerade auf deinen Homescreen synchronisiert." },
    ko: { title: `${name}님이 위젯에 메모를 남겼어요 💌`, body: "홈 화면에 곧 반영돼요." },
    pt: { title: `${name} deixou uma nota no teu widget 💌`, body: "A sincronizar para o ecrã inicial." },
    es: { title: `${name} dejó una nota en tu widget 💌`, body: "Se está sincronizando en tu pantalla de inicio." },
  };
  return t[lang];
}

export function widgetPhotoPush(name: string, lang: MissuoLang): { title: string; body: string } {
  const t: Record<MissuoLang, { title: string; body: string }> = {
    en: { title: `${name} sent a photo to your widget 📸`, body: "It's syncing to your Polaroid now." },
    fr: { title: `${name} a envoyé une photo sur ton widget 📸`, body: "Elle arrive sur ton Polaroid." },
    de: { title: `${name} hat ein Foto an dein Widget geschickt 📸`, body: "Es wird auf dein Polaroid synchronisiert." },
    ko: { title: `${name}님이 위젯으로 사진을 보냈어요 📸`, body: "폴라로이드에 곧 나타나요." },
    pt: { title: `${name} enviou uma foto para o teu widget 📸`, body: "A chegar ao teu Polaroid." },
    es: { title: `${name} envió una foto a tu widget 📸`, body: "Llegando a tu Polaroid." },
  };
  return t[lang];
}

export function meetupPush(name: string, lang: MissuoLang): { title: string; body: string } {
  const t: Record<MissuoLang, { title: string; body: string }> = {
    en: { title: `${name} logged a hug 🤗`, body: "Your Hug Meter is back to day zero." },
    fr: { title: `${name} a enregistré un câlin 🤗`, body: "Votre compteur de câlins repart à zéro." },
    de: { title: `${name} hat eine Umarmung eingetragen 🤗`, body: "Euer Umarmungszähler steht wieder auf null." },
    ko: { title: `${name}님이 포옹을 기록했어요 🤗`, body: "포옹 미터가 다시 0일로 돌아갔어요." },
    pt: { title: `${name} registou um abraço 🤗`, body: "O vosso medidor de abraços voltou ao zero." },
    es: { title: `${name} registró un abrazo 🤗`, body: "Vuestro medidor de abrazos vuelve a cero." },
  };
  return t[lang];
}

export function tomorrowEventPush(title: string, lang: MissuoLang): { title: string; body: string } {
  const t: Record<MissuoLang, { title: string; body: string }> = {
    en: { title: `Tomorrow: ${title} 💛`, body: "One more sleep — anything left to plan together?" },
    fr: { title: `Demain : ${title} 💛`, body: "Encore une nuit — quelque chose à prévoir ensemble ?" },
    de: { title: `Morgen: ${title} 💛`, body: "Noch eine Nacht — gibt es noch etwas zu planen?" },
    ko: { title: `내일: ${title} 💛`, body: "하루만 더 — 함께 계획할 게 남았나요?" },
    pt: { title: `Amanhã: ${title} 💛`, body: "Mais uma noite — falta planear algo juntos?" },
    es: { title: `Mañana: ${title} 💛`, body: "Una noche más — ¿queda algo por planear juntos?" },
  };
  return t[lang];
}

export function premiumUnlockedPush(name: string, lang: MissuoLang): { title: string; body: string } {
  const t: Record<MissuoLang, { title: string; body: string }> = {
    en: { title: `${name} unlocked Premium for you two 👑`, body: "Everything is open on your side too — enjoy it together." },
    fr: { title: `${name} a débloqué Premium pour vous deux 👑`, body: "Tout est ouvert de ton côté aussi — profitez-en ensemble." },
    de: { title: `${name} hat Premium für euch beide freigeschaltet 👑`, body: "Auch bei dir ist jetzt alles offen — genießt es zusammen." },
    ko: { title: `${name}님이 두 사람을 위해 프리미엄을 열었어요 👑`, body: "이제 모든 기능을 함께 쓸 수 있어요." },
    pt: { title: `${name} desbloqueou o Premium para os dois 👑`, body: "Está tudo aberto do teu lado também — aproveitem juntos." },
    es: { title: `${name} desbloqueó Premium para los dos 👑`, body: "Todo está abierto también en tu lado — disfrutadlo juntos." },
  };
  return t[lang];
}

export const pushCopy = {
  answersUnlockedTitle,
  answersUnlockedBody,
  partnerAnsweredTitle,
  partnerAnsweredBody,
  moodTitle,
  moodBody,
};
