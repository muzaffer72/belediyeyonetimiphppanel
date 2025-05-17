import { createRoot } from "react-dom/client";
import { StrictMode } from "react";
import App from "./App";
import "./index.css";

const rootElement = document.getElementById("root");
if (!rootElement) throw new Error("Root element not found");

try {
  const root = createRoot(rootElement);
  root.render(
    <StrictMode>
      <App />
    </StrictMode>
  );
  console.log("React uygulaması başarıyla render edildi.");
} catch (error) {
  console.error("React uygulaması render edilirken hata oluştu:", error);
  
  // Hata durumunda basit bir içerik göster
  rootElement.innerHTML = `
    <div style="padding: 20px; font-family: sans-serif; text-align: center;">
      <h1>Uygulama Yüklenirken Hata Oluştu</h1>
      <p>Lütfen tarayıcı konsolunu kontrol edin ve sayfayı yenileyin.</p>
    </div>
  `;
}
