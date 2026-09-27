interface GradientTextProps {
  children: React.ReactNode;
  className?: string;
  colors?: string[];
  animationSpeed?: number;
}

const GradientText: React.FC<GradientTextProps> = ({
  children,
  className = "",
  colors = ["#60A5FA", "#A78BFA", "#F472B6", "#60A5FA"],
  animationSpeed = 5,
}) => {
  const gradient = colors.join(", ");

  return (
    <span
      className={className}
      style={{
        backgroundImage: `linear-gradient(90deg, ${gradient})`,
        backgroundSize: "300% 100%",
        backgroundClip: "text",
        WebkitBackgroundClip: "text",
        color: "transparent",
        WebkitTextFillColor: "transparent",
        animation: `gradientFlow ${animationSpeed}s ease infinite`,
        display: "inline-block",
      }}
    >
      <style>{`@keyframes gradientFlow { 0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; } }`}</style>
      {children}
    </span>
  );
};

export default GradientText;
