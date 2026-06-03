const defaultModels = {
  gpt: "gpt-4.1-mini",
  gemini: "gemini-2.0-flash",
  deepseek: "deepseek-chat"
};

const els = {
  modelStatus: document.querySelector("#modelStatus"),
  savedModelNotice: document.querySelector("#savedModelNotice"),
  provider: document.querySelector("#provider"),
  model: document.querySelector("#model"),
  apiKey: document.querySelector("#apiKey"),
  saveSettings: document.querySelector("#saveSettings"),
  testModel: document.querySelector("#testModel"),
  clearSettings: document.querySelector("#clearSettings"),
  settingsMessage: document.querySelector("#settingsMessage"),
  sourceText: document.querySelector("#sourceText"),
  charCount: document.querySelector("#charCount"),
  clearText: document.querySelector("#clearText"),
  generate: document.querySelector("#generate"),
  workingNotice: document.querySelector("#workingNotice"),
  fileInput: document.querySelector("#fileInput"),
  fileStatus: document.querySelector("#fileStatus"),
  clearFile: document.querySelector("#clearFile"),
  generateFile: document.querySelector("#generateFile"),
  downloadFile: document.querySelector("#downloadFile"),
  result: document.querySelector("#result"),
  copyResultInline: document.querySelector("#copyResultInline"),
  generateMessage: document.querySelector("#generateMessage")
};

let lastDownload = null;
let savedSettings = null;

function setBusy(button, busy, text) {
  button.disabled = busy;
  if (busy) {
    button.dataset.oldText = button.textContent;
    button.textContent = text;
  } else if (button.dataset.oldText) {
    button.textContent = button.dataset.oldText;
  }
}

function setGenerating(busy, message) {
  els.generate.disabled = busy;
  els.generateFile.disabled = busy;
  if (els.workingNotice) {
    els.workingNotice.hidden = !busy;
    if (message) els.workingNotice.textContent = message;
  }
}

function getMode() {
  return document.querySelector("input[name='mode']:checked").value;
}

function friendlyError(message) {
  const map = {
    "Please finish model settings first.": "请先完成模型设置。",
    "Please save model settings first.": "请先保存模型设置。",
    "Please enter an API Key.": "请填写 API Key。",
    "Please enter source text.": "请输入需要处理的文字。",
    "Short text input is currently limited to 5000 characters.": "短文本输入暂时限制在5000字符以内。",
    "Please choose GPT, Gemini, or DeepSeek.": "请选择 GPT、Gemini 或 DeepSeek。",
    "Unknown model provider.": "未知模型供应商。",
    "Request JSON parse failed.": "请求内容解析失败，请刷新页面后重试。"
  };
  return map[message] || message;
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...(options.headers || {})
    }
  });
  const data = await response.json();
  if (!response.ok || data.ok === false) {
    throw new Error(friendlyError(data.error || "请求失败"));
  }
  return data;
}

function readFileAsBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = String(reader.result || "");
      resolve(result.includes(",") ? result.split(",").pop() : result);
    };
    reader.onerror = () => reject(reader.error || new Error("文件读取失败"));
    reader.readAsDataURL(file);
  });
}

function downloadBase64File(fileName, base64, mimeType) {
  const link = document.createElement("a");
  link.href = `data:${mimeType};base64,${base64}`;
  link.download = fileName;
  document.body.appendChild(link);
  link.click();
  link.remove();
}

async function loadSettings() {
  const settings = await requestJson("/api/settings");
  savedSettings = settings;
  els.provider.value = settings.provider;
  els.model.value = settings.model || defaultModels[settings.provider] || "";
  els.modelStatus.textContent = settings.hasApiKey
    ? `已配置：${settings.provider.toUpperCase()} / ${settings.model}`
    : "未配置模型，请先填写 API Key";
  updateSavedNotice(false);
}

function updateSavedNotice(hasUnsavedChange = false) {
  if (!savedSettings?.hasApiKey) {
    els.savedModelNotice.classList.add("warning");
    els.savedModelNotice.textContent = "当前未保存 API Key。请选择模型并保存 API Key 后再生成提示词。";
    return;
  }

  const changed =
    els.provider.value !== savedSettings.provider ||
    els.model.value.trim() !== savedSettings.model;

  if (hasUnsavedChange || changed) {
    els.savedModelNotice.classList.add("warning");
    els.savedModelNotice.textContent =
      `当前已保存：${savedSettings.provider.toUpperCase()} / ${savedSettings.model}，API Key 已保存在本机。你正在修改为：${els.provider.value.toUpperCase()} / ${els.model.value.trim() || "未填写模型名"}，点击“保存设置”后才会切换。`;
    return;
  }

  els.savedModelNotice.classList.remove("warning");
  els.savedModelNotice.textContent =
    `当前正在使用：${savedSettings.provider.toUpperCase()} / ${savedSettings.model}，API Key 已保存在本机。`;
}

els.provider.addEventListener("change", () => {
  els.model.value = defaultModels[els.provider.value] || "";
  updateSavedNotice(true);
});

els.model.addEventListener("input", () => {
  updateSavedNotice(true);
});

els.sourceText.addEventListener("input", () => {
  els.charCount.textContent = `${els.sourceText.value.length} / 5000`;
});

els.clearText.addEventListener("click", () => {
  els.sourceText.value = "";
  els.charCount.textContent = "0 / 5000";
  els.sourceText.focus();
});

els.fileInput.addEventListener("change", () => {
  const file = els.fileInput.files[0];
  lastDownload = null;
  els.downloadFile.disabled = true;
  els.fileStatus.textContent = file ? `已选择：${file.name}` : "尚未选择文件";
});

els.clearFile.addEventListener("click", () => {
  els.fileInput.value = "";
  els.fileStatus.textContent = "尚未选择文件";
  lastDownload = null;
  els.downloadFile.disabled = true;
  els.generateMessage.textContent = "已清除所选文件。";
});

els.saveSettings.addEventListener("click", async () => {
  els.settingsMessage.textContent = "";
  setBusy(els.saveSettings, true, "保存中");
  try {
    await requestJson("/api/settings", {
      method: "POST",
      body: JSON.stringify({
        provider: els.provider.value,
        model: els.model.value.trim(),
        apiKey: els.apiKey.value.trim()
      })
    });
    els.apiKey.value = "";
    els.settingsMessage.textContent = "模型设置已保存。";
    await loadSettings();
  } catch (error) {
    els.settingsMessage.textContent = error.message;
  } finally {
    setBusy(els.saveSettings, false);
  }
});

els.clearSettings.addEventListener("click", async () => {
  els.settingsMessage.textContent = "";
  setBusy(els.clearSettings, true, "清除中");
  try {
    await requestJson("/api/settings", { method: "DELETE" });
    els.apiKey.value = "";
    els.settingsMessage.textContent = "已清除本机保存的 API Key。";
    await loadSettings();
  } catch (error) {
    els.settingsMessage.textContent = error.message;
  } finally {
    setBusy(els.clearSettings, false);
  }
});

els.testModel.addEventListener("click", async () => {
  els.settingsMessage.textContent = "";
  setBusy(els.testModel, true, "测试中");
  try {
    const data = await requestJson("/api/test-model", { method: "POST", body: "{}" });
    els.settingsMessage.textContent = data.content || "连接成功。";
  } catch (error) {
    els.settingsMessage.textContent = error.message;
  } finally {
    setBusy(els.testModel, false);
  }
});

els.generate.addEventListener("click", async () => {
  els.generateMessage.textContent = "";
  els.result.value = "正在生成提示词，请稍候...";
  setGenerating(true, "正在调用模型生成提示词，请稍候。复杂对话场景可能需要几十秒。");
  setBusy(els.generate, true, "生成中");
  try {
    const data = await requestJson("/api/generate-short", {
      method: "POST",
      body: JSON.stringify({
        mode: getMode(),
        text: els.sourceText.value
      })
    });
    els.result.value = data.content;
    els.generateMessage.textContent = "提示词生成完成。";
  } catch (error) {
    els.result.value = "";
    els.generateMessage.textContent = error.message;
  } finally {
    setBusy(els.generate, false);
    setGenerating(false);
  }
});

els.generateFile.addEventListener("click", async () => {
  const file = els.fileInput.files[0];
  els.generateMessage.textContent = "";
  els.result.value = "";
  lastDownload = null;
  els.downloadFile.disabled = true;

  if (!file) {
    els.generateMessage.textContent = "请先选择 Excel 或 Word 文件。";
    return;
  }

  setBusy(els.generateFile, true, "生成中");
  setGenerating(true, "正在读取文件并调用模型生成提示词，请稍候。批量文件可能需要更久。");
  try {
    const base64 = await readFileAsBase64(file);
    const data = await requestJson("/api/generate-file", {
      method: "POST",
      body: JSON.stringify({
        mode: getMode(),
        fileName: file.name,
        base64
      })
    });
    els.result.value = data.content || "";
    if (data.downloadBase64) {
      lastDownload = {
        fileName: data.downloadName || "织梦师SEEDANCE提示词.docx",
        base64: data.downloadBase64
      };
      els.downloadFile.disabled = false;
      els.generateMessage.textContent = "文件处理完成，可下载 Word 文档。";
    }
  } catch (error) {
    els.generateMessage.textContent = error.message;
  } finally {
    setBusy(els.generateFile, false);
    setGenerating(false);
  }
});

els.downloadFile.addEventListener("click", () => {
  if (!lastDownload) {
    els.generateMessage.textContent = "暂无可下载的 Word 文档。";
    return;
  }
  downloadBase64File(
    lastDownload.fileName,
    lastDownload.base64,
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
  );
});

els.copyResultInline.addEventListener("click", async () => {
  if (!els.result.value || els.result.value === "正在生成提示词，请稍候...") {
    els.generateMessage.textContent = "暂无可复制内容。";
    return;
  }
  await navigator.clipboard.writeText(els.result.value);
  els.generateMessage.textContent = "已复制到剪贴板。";
});

loadSettings().catch((error) => {
  els.modelStatus.textContent = "模型设置读取失败";
  els.settingsMessage.textContent = error.message;
});
