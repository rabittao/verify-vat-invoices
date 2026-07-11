function escapeTimingValue(value) {
  return String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

function formatTimingValue(value) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }

  const text = String(value);
  if (/^[A-Za-z0-9_.:-]+$/.test(text)) {
    return text;
  }
  return `"${escapeTimingValue(text)}"`;
}

function formatTimingLog(stage, durationMs, metadata = {}) {
  const fields = [
    "[timing]",
    `stage=${stage}`,
    `duration_ms=${Math.round(durationMs)}`,
  ];

  for (const [key, value] of Object.entries(metadata)) {
    const formattedValue = formatTimingValue(value);
    if (formattedValue !== null) {
      fields.push(`${key}=${formattedValue}`);
    }
  }

  return fields.join(" ");
}

async function measureAsync(stage, operation, metadata = {}, logger = console.log, now = Date.now) {
  const startedAt = now();
  let error = null;
  try {
    return await operation();
  } catch (caughtError) {
    error = caughtError;
    throw caughtError;
  } finally {
    const finalMetadata = error
      ? { ...metadata, outcome: "error", error: error.message || String(error) }
      : metadata;
    logger(formatTimingLog(stage, now() - startedAt, finalMetadata));
  }
}

function createTimingSpan(stage, metadata = {}, logger = console.log, now = Date.now) {
  const startedAt = now();
  return (extraMetadata = {}) => {
    logger(formatTimingLog(stage, now() - startedAt, { ...metadata, ...extraMetadata }));
  };
}

module.exports = {
  createTimingSpan,
  formatTimingLog,
  measureAsync,
};
