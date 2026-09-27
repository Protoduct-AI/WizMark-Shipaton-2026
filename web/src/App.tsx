import { useEffect, useMemo } from "react";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { useTranslation } from "react-i18next";
import i18n from "./i18n/config";
import CardNav from "./components/CardNav";
import LanguageSwitcher from "./components/LanguageSwitcher";
import Landing from "./pages/Landing";
import Privacy from "./pages/Privacy";
import Terms from "./pages/Terms";
import Join from "./pages/Join";

const APP_STORE_URL = "https://apps.apple.com/app/id6784499093";

function useLocalizedMeta() {
  const { t } = useTranslation();
  useEffect(() => {
    document.documentElement.lang = i18n.language;
    document.title = t("meta.title");
    const setMeta = (name: string, content: string) => {
      let el = document.querySelector<HTMLMetaElement>(`meta[name="${name}"]`);
      if (el) el.setAttribute("content", content);
    };
    setMeta("description", t("meta.description"));
  }, [i18n.language, t]);
}

export default function App() {
  const { t } = useTranslation();
  useLocalizedMeta();

  const navItems = useMemo(
    () => [
      {
        label: t("nav.legalLabel"),
        bgColor: "#1B1722",
        textColor: "#fff",
        links: [
          { label: t("nav.privacy"), href: "/privacy", ariaLabel: t("nav.privacy") },
          { label: t("nav.terms"), href: "/terms", ariaLabel: t("nav.terms") },
        ],
      },
      {
        label: t("nav.appLabel"),
        bgColor: "#2F293A",
        textColor: "#fff",
        links: [
          { label: t("nav.appStore"), href: APP_STORE_URL, ariaLabel: t("nav.appStore") },
        ],
      },
    ],
    [t]
  );

  const ctaBadgeAlt = t("hero.appStoreBadgeAlt");

  return (
    <BrowserRouter>
      <CardNav
        logoText="WizMark"
        items={navItems}
        baseColor="#0f0f17"
        menuColor="#ffffff"
        ctaBadge="/appstore-badge-white.svg"
        ctaBadgeAlt={ctaBadgeAlt}
        ctaHref={APP_STORE_URL}
        localeSwitcher={<LanguageSwitcher />}
      />
      <Routes>
        <Route path="/" element={<Landing />} />
        <Route path="/privacy" element={<Privacy />} />
        <Route path="/terms" element={<Terms />} />
        <Route path="/join/:code" element={<Join />} />
        <Route
          path="*"
          element={
            <div style={{ padding: "80px 40px", textAlign: "center", color: "#f0f0f8" }}>
              <h1>404</h1>
              <p>Page not found</p>
              <a href="/" style={{ color: "#60A5FA" }}>Back to home</a>
            </div>
          }
        />
      </Routes>
    </BrowserRouter>
  );
}
