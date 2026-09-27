import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";

const CONVEX_SITE_URL = "https://vibrant-basilisk-719.convex.site";
const APP_STORE_URL = "https://apps.apple.com/app/id6784499093";
const APP_SCHEME = "wizmark";

interface SharePreview {
  name: string;
  icon: string | null;
  color: string | null;
  ownerName: string | null;
  bookmarkCount: number;
}

type LoadState =
  | { status: "loading" }
  | { status: "ready"; preview: SharePreview }
  | { status: "missing" }
  | { status: "error" };

/**
 * Landing page for an invitation link.
 *
 * A universal link usually opens WizMark directly, but not always: pasting the
 * URL into the address bar, or opening it from a same-domain page, lands here
 * even with the app installed. So this page has to serve both audiences — a
 * custom-scheme button for people who already have the app, and the App Store
 * for everyone else — while saying what the invitation is actually for.
 */
export default function Join() {
  const { code } = useParams<{ code: string }>();
  const { t } = useTranslation();
  const [state, setState] = useState<LoadState>({ status: "loading" });

  useEffect(() => {
    if (!code) {
      setState({ status: "missing" });
      return;
    }

    let cancelled = false;

    (async () => {
      try {
        const response = await fetch(
          `${CONVEX_SITE_URL}/share-preview?code=${encodeURIComponent(code)}`,
        );
        if (cancelled) return;

        if (response.status === 404) {
          setState({ status: "missing" });
          return;
        }
        if (!response.ok) {
          setState({ status: "error" });
          return;
        }

        setState({ status: "ready", preview: (await response.json()) as SharePreview });
      } catch {
        if (!cancelled) setState({ status: "error" });
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [code]);

  return (
    <div className="join-page">
      <div className="join-card">
        {state.status === "loading" && <p className="join-muted">{t("join.loading")}</p>}

        {state.status === "ready" && (
          <>
            <p className="join-eyebrow">
              {state.preview.ownerName
                ? t("join.invitedBy", { name: state.preview.ownerName })
                : t("join.invitedGeneric")}
            </p>

            <h1 className="join-title">{state.preview.name}</h1>

            <p className="join-muted">
              {t("join.bookmarkCount", { count: state.preview.bookmarkCount })}
            </p>

            <a className="join-cta" href={`${APP_SCHEME}://join/${code}`}>
              {t("join.openInApp")}
            </a>

            <p className="join-note">{t("join.openInAppNote")}</p>

            <a className="join-cta join-cta-secondary" href={APP_STORE_URL}>
              {t("join.getApp")}
            </a>

            <p className="join-note">{t("join.afterInstall")}</p>
          </>
        )}

        {state.status === "missing" && (
          <>
            <h1 className="join-title">{t("join.unavailableTitle")}</h1>
            <p className="join-muted">{t("join.unavailableBody")}</p>
            <a className="join-cta" href={APP_STORE_URL}>
              {t("join.getApp")}
            </a>
          </>
        )}

        {state.status === "error" && (
          <>
            <h1 className="join-title">{t("join.errorTitle")}</h1>
            <p className="join-muted">{t("join.errorBody")}</p>
          </>
        )}

        <Link className="join-home" to="/">
          {t("footer.home")}
        </Link>
      </div>
    </div>
  );
}
