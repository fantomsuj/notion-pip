import Image from "next/image";
import { introDoneMs } from "@/lib/intro-motion";

export function PageIntro() {
  return (
    <div className="page-intro" id="page-intro">
      <div className="page-loader" aria-hidden>
        <Image
          src="/perch-bird.png"
          alt=""
          width={64}
          height={64}
          priority
          sizes="56px"
          className="page-loader-mark size-14 object-contain"
        />
        <span className="page-loader-wordmark">Perch</span>
        <span className="page-loader-track">
          <span className="page-loader-bar" />
        </span>
      </div>
      <script
        dangerouslySetInnerHTML={{
          __html: `setTimeout(function(){var e=document.getElementById("page-intro");if(e)e.setAttribute("data-intro-done","")},${introDoneMs})`,
        }}
      />
    </div>
  );
}
