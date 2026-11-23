/** A card's stamps as dots: filled for each stamp, hollow for each still to come. */
export function Dots({ stamps, goal }: { stamps: number; goal: number }) {
  return (
    <span aria-hidden="true" style={{ display: "inline-flex", gap: 6, direction: "ltr" }}>
      {Array.from({ length: goal }, (_, i) => (
        <span
          key={i}
          style={{
            inlineSize: 18,
            blockSize: 18,
            borderRadius: "50%",
            border: "2px solid currentColor",
            background: i < stamps ? "currentColor" : "transparent",
          }}
        />
      ))}
    </span>
  );
}
