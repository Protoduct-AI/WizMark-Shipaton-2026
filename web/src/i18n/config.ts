import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';
import LanguageDetector from 'i18next-browser-languagedetector';
import en from './locales/en.json';
import ja from './locales/ja.json';

export const SUPPORTED_LANGS = ['en', 'ja'] as const;
export type AppLang = (typeof SUPPORTED_LANGS)[number];

i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources: {
      en: { translation: en },
      ja: { translation: ja },
    },
    fallbackLng: 'en',
    supportedLngs: [...SUPPORTED_LANGS],
    detection: {
      order: ['localStorage', 'navigator', 'htmlTag'],
      lookupLocalStorage: 'wizmark-lang',
      caches: ['localStorage'],
    },
    interpolation: { escapeValue: false },
    returnObjects: true,
  });

export default i18n;
