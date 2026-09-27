interface AuroraProps {
  colorStops?: string[];
  blend?: number;
  amplitude?: number;
  speed?: number;
}

export default function Aurora({
  colorStops = ["#3B82F6", "#8B5CF6", "#06B6D4"],
  blend = 0.5,
  amplitude = 1.0,
  speed = 0.5,
}: AuroraProps) {
  const id = "aurora-" + Math.random().toString(36).slice(2, 8);
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        overflow: "hidden",
        zIndex: 0,
        opacity: blend,
      }}
    >
      <svg width="100%" height="100%" style={{ position: "absolute", inset: 0 }}>
        <defs>
          <filter id={id}>
            <feTurbulence
              type="fractalNoise"
              baseFrequency="0.01"
              numOctaves="3"
              seed="1"
            >
              <animate
                attributeName="baseFrequency"
                values={`0.01;${0.01 + 0.005 * amplitude};0.01`}
                dur={`${10 / speed}s`}
                repeatCount="indefinite"
              />
            </feTurbulence>
            <feDisplacementMap in="SourceGraphic" scale={`${80 * amplitude}`} />
          </filter>
        </defs>
        <g filter={`url(#${id})`}>
          {colorStops.map((color, i) => (
            <circle
              key={i}
              cx={`${25 + i * 25}%`}
              cy="50%"
              r="30%"
              fill={color}
              opacity="0.4"
            >
              <animate
                attributeName="cy"
                values={`${40 + i * 10}%;${60 - i * 5}%;${40 + i * 10}%`}
                dur={`${6 + i * 2}s`}
                repeatCount="indefinite"
              />
            </circle>
          ))}
        </g>
      </svg>
    </div>
  );
}
