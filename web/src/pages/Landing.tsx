import { useTranslation } from "react-i18next";
import GradientText from "../components/GradientText";
import SplitText from "../components/SplitText";
import Lightfall from "../components/Lightfall";

export default function Landing() {
  const { t, i18n } = useTranslation();

  return (
    <>
      <section className="hero">
        <div className="hero-bg">
          <Lightfall
            colors={["#60A5FA", "#8B5CF6", "#C084FC"]}
            backgroundColor="#080810"
            speed={0.3}
            streakCount={4}
            streakWidth={0.8}
            streakLength={1.2}
            glow={0.6}
            density={0.4}
            twinkle={0.8}
            zoom={3}
            backgroundGlow={0.3}
            opacity={0.5}
            mouseInteraction={true}
            mouseStrength={0.4}
            mouseRadius={0.8}
          />
        </div>
        <div className="hero-inner">
          <div className="hero-text">
            <h1>
              <SplitText key={i18n.language} text={t("hero.line1")} delay={50} />
              <br />
              <GradientText
                colors={["#60A5FA", "#C084FC", "#F472B6", "#60A5FA"]}
                animationSpeed={4}
              >
                {t("hero.line2")}
              </GradientText>
            </h1>

            <a
              href="https://apps.apple.com/app/id6784499093"
              className="appstore-badge"
              aria-label={t("hero.appStoreBadgeAlt")}
              target="_blank"
              rel="noopener noreferrer"
            >
              <img
                src="/appstore-badge-white.svg"
                alt={t("hero.appStoreBadgeAlt")}
                className="appstore-badge-img"
              />
            </a>
          </div>

          <div className="hero-visual">
            <div className="phone-frame">
              <img src="/screenshot1.png" alt={t("hero.screenshotHomeAlt")} />
            </div>
            <div className="phone-frame phone-frame-offset">
              <img src="/screenshot2.png" alt={t("hero.screenshotDetailAlt")} />
            </div>
          </div>
        </div>
      </section>
    </>
  );
}
