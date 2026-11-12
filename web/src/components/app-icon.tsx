import Image from "next/image";

/** App artwork keeps its own colors in both site themes. Names appear alongside. */
export function AppIcon({ src, size = 44 }: { src: string; size?: number }) {
  return (
    <Image
      src={src}
      alt=""
      width={size}
      height={size}
      className="shrink-0 rounded-[24%] bg-white object-cover ring-1 ring-ink/10"
    />
  );
}
