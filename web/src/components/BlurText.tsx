import { useEffect, useRef, useMemo, useCallback } from "react";

interface BlurTextProps {
  text: string;
  delay?: number;
  className?: string;
}

export default function BlurText({ text, delay = 50, className = "" }: BlurTextProps) {
  const ref = useRef<HTMLSpanElement>(null);
  const words = useMemo(() => text.split(" "), [text]);

  const animate = useCallback(() => {
    const spans = ref.current?.querySelectorAll("span");
    spans?.forEach((span, i) => {
      setTimeout(() => {
        span.style.filter = "blur(0px)";
        span.style.opacity = "1";
        span.style.transform = "translateY(0)";
      }, i * delay);
    });
  }, [delay]);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => { if (entry.isIntersecting) { animate(); observer.disconnect(); } },
      { threshold: 0.1 }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [animate]);

  return (
    <span ref={ref} className={className}>
      {words.map((word, i) => (
        <span
          key={i}
          style={{
            display: "inline-block",
            filter: "blur(8px)",
            opacity: 0,
            transform: "translateY(8px)",
            transition: "all 0.6s cubic-bezier(0.16,1,0.3,1)",
            marginRight: "0.3em",
          }}
        >
          {word}
        </span>
      ))}
    </span>
  );
}
