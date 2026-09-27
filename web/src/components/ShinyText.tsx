interface ShinyTextProps {
  children: React.ReactNode;
  className?: string;
  speed?: number;
}

export default function ShinyText({ children, className = "", speed = 3 }: ShinyTextProps) {
  return (
    <span
      className={className}
      style={{
        background: "linear-gradient(120deg, rgba(255,255,255,0) 40%, rgba(255,255,255,0.6) 50%, rgba(255,255,255,0) 60%)",
        backgroundSize: "200% 100%",
        WebkitBackgroundClip: "text",
        WebkitTextFillColor: "transparent",
        animation: `shiny ${speed}s linear infinite`,
        backgroundClip: "text",
      }}
    >
      <style>{`@keyframes shiny { 0% { background-position: 200% 0; } 100% { background-position: -200% 0; } }`}</style>
      {children}
    </span>
  );
}
