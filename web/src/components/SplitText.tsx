import { useMemo, useRef, useEffect, useCallback } from "react";

interface SplitTextProps {
  text: string;
  className?: string;
  delay?: number;
  animationFrom?: Record<string, string | number>;
  animationTo?: Record<string, string | number>;
  threshold?: number;
  rootMargin?: string;
  onLetterAnimationComplete?: () => void;
}

const SplitText: React.FC<SplitTextProps> = ({
  text,
  className = "",
  delay = 50,
  animationFrom = { opacity: 0, transform: "translate3d(0,40px,0)" },
  animationTo = { opacity: 1, transform: "translate3d(0,0,0)" },
  threshold = 0.1,
  rootMargin = "-100px",
  onLetterAnimationComplete,
}) => {
  const ref = useRef<HTMLSpanElement>(null);
  const letterRefs = useRef<(HTMLSpanElement | null)[]>([]);

  const letters = useMemo(() => text.split(""), [text]);

  const animate = useCallback(() => {
    letterRefs.current.forEach((letter, i) => {
      if (!letter) return;
      Object.assign(letter.style, animationFrom);
      setTimeout(() => {
        Object.assign(letter.style, {
          ...animationTo,
          transition: `all 0.5s cubic-bezier(0.16,1,0.3,1)`,
        });
        if (i === letters.length - 1) onLetterAnimationComplete?.();
      }, i * delay);
    });
  }, [animationFrom, animationTo, delay, letters.length, onLetterAnimationComplete]);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => { if (entry.isIntersecting) { animate(); observer.disconnect(); } },
      { threshold, rootMargin }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [animate, threshold, rootMargin]);

  return (
    <span ref={ref} className={className} style={{ display: "inline" }}>
      {letters.map((l, i) => (
        <span
          key={i}
          ref={(el) => { letterRefs.current[i] = el; }}
          style={{ display: "inline-block", opacity: 0, whiteSpace: l === " " ? "pre" : undefined, color: "inherit", WebkitTextFillColor: "inherit" }}
        >
          {l}
        </span>
      ))}
    </span>
  );
};

export default SplitText;
