import { defineConfig } from "deepsec/config";

export default defineConfig({
  projects: [
    { id: "Tungsten", root: ".." },
    // <deepsec:projects-insert-above>
  ],
});
