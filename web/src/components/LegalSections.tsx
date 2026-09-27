import { useTranslation } from "react-i18next";

interface LegalSub {
  heading: string;
  body?: string;
  items?: string[];
}
interface LegalSection {
  heading: string;
  body?: string;
  items?: string[];
  subsections?: LegalSub[];
}
interface LegalDoc {
  title: string;
  updated: string;
  sections: LegalSection[];
}

const CONTACT_EMAIL = "protoduct3@gmail.com";

/**
 * Privacy / Terms の共通レンダラ。
 * i18n の構造化 JSON（{ title, updated, sections[] }）から描画する。
 * 両文書とも最終セクションが「お問い合わせ」で、その直後にメールアドレスを表示する。
 */
export default function LegalSections({ docKey }: { docKey: "privacy" | "terms" }) {
  const { t } = useTranslation();
  const doc = t(docKey, { returnObjects: true }) as LegalDoc;
  if (!doc?.sections) return null;

  return (
    <div className="container legal">
      <h1>{doc.title}</h1>
      <p className="date">{doc.updated}</p>

      {doc.sections.map((section, idx) => (
        <section key={`${docKey}-${idx}`}>
          <h2>{section.heading}</h2>
          {section.body && <p>{section.body}</p>}
          {section.items && (
            <ul>
              {section.items.map((item, i) => (
                <li key={`it-${idx}-${i}`}>{item}</li>
              ))}
            </ul>
          )}
          {section.subsections?.map((sub, si) => (
            <div key={`sub-${idx}-${si}`}>
              <h3>{sub.heading}</h3>
              {sub.body && <p>{sub.body}</p>}
              {sub.items && (
                <ul>
                  {sub.items.map((item, i) => (
                    <li key={`sit-${idx}-${si}-${i}`}>{item}</li>
                  ))}
                </ul>
              )}
            </div>
          ))}
        </section>
      ))}

      {/* お問い合わせ先（最終セクション直後） */}
      <p>
        {t("contact.emailLabel")}:{" "}
        <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>
      </p>
    </div>
  );
}
