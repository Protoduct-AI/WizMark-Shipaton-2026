import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import LegalSections from "../components/LegalSections";

export default function Privacy() {
  const { t } = useTranslation();

  return (
    <>
      <LegalSections docKey="privacy" />

      <footer>
        <div className="footer-links">
          <Link to="/">{t("footer.home")}</Link>
          <Link to="/terms">{t("footer.terms")}</Link>
        </div>
        <p>{t("footer.copyright")}</p>
      </footer>
    </>
  );
}
