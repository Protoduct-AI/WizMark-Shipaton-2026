import { useTranslation } from 'react-i18next';
import { SUPPORTED_LANGS, type AppLang } from '../i18n/config';

export default function LanguageSwitcher() {
  const { i18n, t } = useTranslation();
  const current = (SUPPORTED_LANGS as readonly string[]).includes(i18n.language)
    ? (i18n.language as AppLang)
    : 'en';

  const change = (lng: AppLang) => {
    i18n.changeLanguage(lng);
  };

  return (
    <div className="lang-switcher" role="group" aria-label="Language">
      {(SUPPORTED_LANGS as readonly AppLang[]).map((lng) => (
        <button
          key={lng}
          type="button"
          className={`lang-switcher-btn ${current === lng ? 'is-active' : ''}`}
          onClick={() => change(lng)}
          aria-pressed={current === lng}
        >
          {t(`lang.${lng}`)}
        </button>
      ))}
    </div>
  );
}
