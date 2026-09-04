import { useEffect, useMemo } from "react";
import { resolvePage } from "./generated/pages";
import { appData } from "./data/appData";
import { mountI18nRuntime } from "./runtime/i18nRuntime";
import { mountAppRuntime } from "./runtime/appRuntime";

export default function App() {
  const page = useMemo(() => resolvePage(window.location.pathname), []);

  useEffect(() => {
    window.RIC_APP_DATA = appData;
    document.title = page?.title ?? "РИЦ Mini App";
    document.documentElement.lang = "ru";
    if (!page) return;
    mountI18nRuntime();
    mountAppRuntime();
    document.dispatchEvent(new Event("DOMContentLoaded", { bubbles: true }));
  }, [page]);

  if (!page) {
    return (
      <main className="route-not-found">
        <h1>Страница не найдена</h1>
        <a href="/">Вернуться на главную</a>
      </main>
    );
  }

  return <div className="react-page-contents" dangerouslySetInnerHTML={{ __html: page.html }} />;
}
