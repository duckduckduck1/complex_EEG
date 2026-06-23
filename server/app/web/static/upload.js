(function () {
  const form = document.querySelector("[data-upload-form]");
  if (!form) {
    return;
  }

  const allowedFiles = splitDataset(form.dataset.allowedFiles);
  const requiredFiles = splitDataset(form.dataset.requiredFiles);
  const csrfToken = form.dataset.csrfToken || "";
  const fileInputs = Array.from(form.querySelectorAll("input[type='file']"));
  const experimentIdInput = form.querySelector("[data-experiment-id]");
  const selectedFilesBox = form.querySelector("[data-selected-files]");
  const submitButton = form.querySelector("[data-submit-upload]");
  const cancelButton = form.querySelector("[data-cancel-upload]");
  const resetButton = form.querySelector("[data-reset-upload]");
  const statusCard = document.querySelector("[data-upload-status]");
  const statusTitle = document.querySelector("[data-upload-status-title]");
  const stepsList = document.querySelector("[data-upload-steps]");
  const resultBox = document.querySelector("[data-upload-result]");
  let activeSession = null;

  fileInputs.forEach((input) => {
    input.addEventListener("change", () => {
      renderSelectedFiles();
      fillExperimentIdFromJson();
    });
  });

  resetButton.addEventListener("click", () => {
    form.reset();
    setResult("");
    clearSteps();
    hideStatus();
    renderSelectedFiles();
  });

  cancelButton.addEventListener("click", async () => {
    if (!activeSession) {
      return;
    }

    setBusy(true);
    showStatus("Отмена upload session");
    clearSteps();
    setResult("");

    try {
      addStep(`Отменяем ${activeSession.upload_session_id}`);
      await apiJson(`/api/v1/uploads/${activeSession.upload_session_id}`, {
        method: "DELETE",
        headers: csrfHeaders(),
      });
      activeSession = null;
      updateCancelButton();
      setResult('<p class="success">Upload session отменена.</p>');
    } catch (error) {
      showError(errorToMessage(error));
    } finally {
      setBusy(false);
    }
  });

  form.addEventListener("submit", async (event) => {
    event.preventDefault();

    let packageFiles;
    try {
      packageFiles = collectPackageFiles();
    } catch (error) {
      showError(errorToMessage(error));
      return;
    }

    const missing = requiredFiles.filter((name) => !packageFiles.has(name));
    if (missing.length > 0) {
      showError(`Не хватает обязательных файлов: ${missing.join(", ")}`);
      return;
    }

    let experimentId = experimentIdInput.value.trim();
    if (!experimentId) {
      experimentId = await readExperimentId(packageFiles.get("experiment.json"));
      experimentIdInput.value = experimentId;
    }
    if (!experimentId) {
      showError("Укажите experiment_id или выберите experiment.json с этим полем.");
      return;
    }

    const expectedFiles = Array.from(packageFiles.keys()).sort(comparePackageFiles);

    setBusy(true);
    showStatus("Загрузка");
    clearSteps();
    setResult("");

    try {
      const session = await getOrCreateSession(experimentId, expectedFiles);

      for (const fileName of expectedFiles) {
        addStep(`Отправляем ${fileName}`);
        await apiJson(`/api/v1/uploads/${session.upload_session_id}/files/${encodeURIComponent(fileName)}`, {
          method: "PUT",
          headers: {
            ...csrfHeaders(),
            "Content-Type": "application/octet-stream",
          },
          body: packageFiles.get(fileName),
        });
      }

      addStep("Запускаем проверку пакета");
      const completed = await apiJson(`/api/v1/uploads/${session.upload_session_id}/complete`, {
        method: "POST",
        headers: csrfHeaders(),
      });

      if (completed.accepted) {
        activeSession = null;
        updateCancelButton();
        showSuccess(completed.experiment_id);
      } else {
        activeSession = null;
        updateCancelButton();
        showValidationFailed(completed);
      }
    } catch (error) {
      showError(errorToMessage(error));
    } finally {
      setBusy(false);
    }
  });

  renderSelectedFiles();

  async function getOrCreateSession(experimentId, expectedFiles) {
    if (activeSession && activeSession.experiment_id === experimentId) {
      addStep(`Продолжаем upload session ${activeSession.upload_session_id}`);
      return activeSession;
    }

    if (activeSession) {
      throw new Error(
        `Уже активна upload session для ${activeSession.experiment_id}. ` +
        "Отмените её перед загрузкой другого experiment_id."
      );
    }

    addStep("Создаём upload session");
    const session = await apiJson("/api/v1/uploads", {
      method: "POST",
      headers: {
        ...csrfHeaders(),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        experiment_id: experimentId,
        expected_files: expectedFiles,
      }),
    });

    activeSession = session;
    updateCancelButton();
    return session;
  }

  function splitDataset(value) {
    return (value || "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  }

  function collectPackageFiles() {
    const result = new Map();
    const duplicates = new Set();

    for (const input of fileInputs) {
      for (const file of Array.from(input.files || [])) {
        if (!allowedFiles.includes(file.name)) {
          continue;
        }
        if (result.has(file.name)) {
          duplicates.add(file.name);
          continue;
        }
        result.set(file.name, file);
      }
    }

    if (duplicates.size > 0) {
      throw new Error(`Выбраны дубликаты файлов пакета: ${Array.from(duplicates).join(", ")}`);
    }

    return result;
  }

  function renderSelectedFiles() {
    try {
      const packageFiles = collectPackageFiles();
      if (packageFiles.size === 0) {
        selectedFilesBox.textContent = "Файлы не выбраны.";
        return;
      }
      selectedFilesBox.textContent = Array.from(packageFiles.entries())
        .sort(([left], [right]) => comparePackageFiles(left, right))
        .map(([name, file]) => `${name} (${formatBytes(file.size)})`)
        .join(", ");
    } catch (error) {
      selectedFilesBox.textContent = error.message;
    }
  }

  async function fillExperimentIdFromJson() {
    if (experimentIdInput.value.trim()) {
      return;
    }

    try {
      const experimentJson = collectPackageFiles().get("experiment.json");
      if (!experimentJson) {
        return;
      }
      const experimentId = await readExperimentId(experimentJson);
      if (experimentId) {
        experimentIdInput.value = experimentId;
      }
    } catch (_error) {
      return;
    }
  }

  async function readExperimentId(file) {
    if (!file) {
      return "";
    }

    try {
      const payload = JSON.parse(await file.text());
      return typeof payload.experiment_id === "string" ? payload.experiment_id.trim() : "";
    } catch (_error) {
      return "";
    }
  }

  async function apiJson(url, options) {
    const response = await fetch(url, {
      credentials: "same-origin",
      ...options,
    });

    const contentType = response.headers.get("content-type") || "";
    const body = contentType.includes("application/json")
      ? await response.json()
      : await response.text();

    if (!response.ok) {
      const error = new Error("Request failed");
      error.status = response.status;
      error.body = body;
      throw error;
    }

    return body;
  }

  function csrfHeaders() {
    return csrfToken ? {"X-CSRF-Token": csrfToken} : {};
  }

  function comparePackageFiles(left, right) {
    const order = ["signal.bin", "experiment.json", "journal.ndjson", "app.log"];
    const leftIndex = order.indexOf(left);
    const rightIndex = order.indexOf(right);
    return (leftIndex === -1 ? order.length : leftIndex)
      - (rightIndex === -1 ? order.length : rightIndex)
      || left.localeCompare(right);
  }

  function formatBytes(value) {
    if (value < 1024) {
      return `${value} Б`;
    }
    if (value < 1024 * 1024) {
      return `${(value / 1024).toFixed(1)} КБ`;
    }
    return `${(value / 1024 / 1024).toFixed(1)} МБ`;
  }

  function showStatus(title) {
    statusCard.hidden = false;
    statusTitle.textContent = title;
  }

  function hideStatus() {
    statusCard.hidden = true;
  }

  function addStep(text) {
    const item = document.createElement("li");
    item.textContent = text;
    stepsList.appendChild(item);
  }

  function clearSteps() {
    stepsList.replaceChildren();
  }

  function setResult(html) {
    resultBox.innerHTML = html;
  }

  function showSuccess(experimentId) {
    showStatus("Пакет принят");
    setResult(`<p class="success">Эксперимент принят. <a href="/experiments/${encodeURIComponent(experimentId)}">Открыть карточку</a></p>`);
  }

  function showValidationFailed(completed) {
    showStatus("Пакет не прошёл проверку");
    const errors = (completed.errors || [])
      .map((error) => `<li><code>${escapeHtml(error.code)}</code>: ${escapeHtml(error.message)}</li>`)
      .join("");
    setResult(`<p class="error">Validation failed.</p><ul>${errors}</ul>`);
  }

  function showError(message) {
    showStatus("Ошибка загрузки");
    clearSteps();
    const retryText = activeSession
      ? "<p class=\"muted\">Можно повторить загрузку с той же session или отменить её.</p>"
      : "";
    setResult(`<p class="error">${escapeHtml(message)}</p>${retryText}`);
    updateCancelButton();
  }

  function errorToMessage(error) {
    if (error && error.body && error.body.detail) {
      const detail = error.body.detail;
      return detail.message || detail.code || `HTTP ${error.status}`;
    }
    return error && error.message ? error.message : "Не удалось загрузить пакет.";
  }

  function setBusy(isBusy) {
    submitButton.disabled = isBusy;
    cancelButton.disabled = isBusy;
    resetButton.disabled = isBusy;
  }

  function updateCancelButton() {
    cancelButton.hidden = !activeSession;
  }

  function escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }
})();
