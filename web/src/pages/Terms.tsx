import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import LegalSections from "../components/LegalSections";

export default function Terms() {
  const { t } = useTranslation();

  return (
    <>
      <LegalSections docKey="terms" />

      <footer>
        <div className="footer-links">
          <Link to="/">{t("footer.home")}</Link>
          <Link to="/privacy">{t("footer.privacy")}</Link>
        </div>
        <p>{t("footer.copyright")}</p>
      </footer>
    </>
  );
}
