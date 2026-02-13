const PLUGIN_DATA_KEY_ID = "uiSchemaId";
const PLUGIN_DATA_KEY_MANAGED = "uiSchemaManaged";

figma.showUI(__html__, { width: 460, height: 680 });

function post(type, payload) {
  figma.ui.postMessage({ type, payload });
}

function toNumber(value, fallback) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function hexToRgb(hex) {
  if (typeof hex !== "string") return null;
  const cleaned = hex.replace("#", "").trim();
  if (!(cleaned.length === 6 || cleaned.length === 8)) return null;
  const base = cleaned.slice(0, 6);
  const alpha = cleaned.length === 8 ? cleaned.slice(6) : null;
  const num = Number.parseInt(base, 16);
  if (Number.isNaN(num)) return null;
  const r = ((num >> 16) & 255) / 255;
  const g = ((num >> 8) & 255) / 255;
  const b = (num & 255) / 255;
  const a = alpha ? Number.parseInt(alpha, 16) / 255 : 1;
  return { r, g, b, a };
}

function normalizeSolidPaint(fillDef) {
  if (typeof fillDef === "string") {
    const rgb = hexToRgb(fillDef);
    if (!rgb) return null;
    return {
      type: "SOLID",
      color: { r: rgb.r, g: rgb.g, b: rgb.b },
      opacity: rgb.a
    };
  }
  if (!fillDef || typeof fillDef !== "object") return null;
  if (fillDef.type && fillDef.type !== "SOLID") return null;
  const rgb = hexToRgb(fillDef.color);
  if (!rgb) return null;
  return {
    type: "SOLID",
    color: { r: rgb.r, g: rgb.g, b: rgb.b },
    opacity: typeof fillDef.opacity === "number" ? fillDef.opacity : rgb.a
  };
}

function hasChildren(node) {
  return "children" in node && typeof node.appendChild === "function";
}

function isManaged(node) {
  return node.getPluginData(PLUGIN_DATA_KEY_MANAGED) === "1";
}

function buildIdIndex() {
  const map = new Map();
  const nodes = figma.currentPage.findAll((node) => node.getPluginData(PLUGIN_DATA_KEY_ID) !== "");
  for (const node of nodes) {
    const id = node.getPluginData(PLUGIN_DATA_KEY_ID);
    if (id) map.set(id, node);
  }
  return map;
}

function validateSchema(schema) {
  const errors = [];
  if (!schema || typeof schema !== "object") {
    errors.push("schema 必须是对象");
    return errors;
  }
  if (schema.version !== "1.0") {
    errors.push("schema.version 必须为 \"1.0\"");
  }
  if (!Array.isArray(schema.frames) || schema.frames.length === 0) {
    errors.push("schema.frames 必须是非空数组");
  }

  const ids = new Set();
  function walk(node, path) {
    if (!node || typeof node !== "object") {
      errors.push(`${path} 必须是对象`);
      return;
    }
    if (typeof node.id !== "string" || node.id.trim() === "") {
      errors.push(`${path}.id 必须是非空字符串`);
    } else if (ids.has(node.id)) {
      errors.push(`重复的 id: ${node.id}`);
    } else {
      ids.add(node.id);
    }
    if (typeof node.name !== "string" || node.name.trim() === "") {
      errors.push(`${path}.name 必须是非空字符串`);
    }
    if (typeof node.type !== "string") {
      errors.push(`${path}.type 必须是字符串`);
    }
    const size = node.size || {};
    if (!Number.isFinite(size.width) || !Number.isFinite(size.height)) {
      errors.push(`${path}.size.width/height 必须是数字`);
    }
    if (node.children && !Array.isArray(node.children)) {
      errors.push(`${path}.children 必须是数组`);
    }
    if (Array.isArray(node.children)) {
      node.children.forEach((child, idx) => walk(child, `${path}.children[${idx}]`));
    }
  }

  if (Array.isArray(schema.frames)) {
    schema.frames.forEach((frame, idx) => walk(frame, `frames[${idx}]`));
  }
  return errors;
}

async function loadFontForText(def) {
  const family = def.fontFamily || "Inter";
  let style = def.fontStyle || "Regular";
  if (!def.fontStyle && typeof def.fontWeight === "number") {
    style = def.fontWeight >= 600 ? "Bold" : "Regular";
  }
  const preferred = { family, style };
  try {
    await figma.loadFontAsync(preferred);
    return preferred;
  } catch (_) {
    const fallback = { family: "Inter", style: "Regular" };
    await figma.loadFontAsync(fallback);
    return fallback;
  }
}

function applyGeometry(node, def) {
  if (def.position) {
    node.x = toNumber(def.position.x, node.x);
    node.y = toNumber(def.position.y, node.y);
  }
  if (def.size) {
    const w = Math.max(1, toNumber(def.size.width, node.width));
    const h = Math.max(1, toNumber(def.size.height, node.height));
    if (typeof node.resize === "function") {
      node.resize(w, h);
    }
  }
}

function applyCommonVisual(node, def) {
  node.name = def.name || node.name;
  node.visible = def.visible !== false;
  node.locked = def.locked === true;
  if (typeof def.opacity === "number") node.opacity = def.opacity;

  if ("cornerRadius" in def && typeof def.cornerRadius === "number" && "cornerRadius" in node) {
    node.cornerRadius = def.cornerRadius;
  }

  if (def.fills && "fills" in node) {
    const paints = def.fills
      .map((fill) => normalizeSolidPaint(fill))
      .filter((fill) => fill !== null);
    if (paints.length > 0) node.fills = paints;
  }

  if (def.strokes && "strokes" in node) {
    const paints = def.strokes
      .map((stroke) => normalizeSolidPaint(stroke))
      .filter((stroke) => stroke !== null);
    node.strokes = paints;
  }

  if (typeof def.strokeWeight === "number" && "strokeWeight" in node) {
    node.strokeWeight = def.strokeWeight;
  }
}

function applyAutoLayout(node, def) {
  if (!("layoutMode" in node)) return;
  const layout = def.layout || {};
  const mode = layout.mode || "NONE";
  node.layoutMode = mode;
  if (mode === "HORIZONTAL" || mode === "VERTICAL") {
    node.primaryAxisSizingMode = layout.primaryAxisSizingMode || "FIXED";
    node.counterAxisSizingMode = layout.counterAxisSizingMode || "FIXED";
    node.primaryAxisAlignItems = layout.primaryAxisAlignItems || "MIN";
    node.counterAxisAlignItems = layout.counterAxisAlignItems || "MIN";
    node.itemSpacing = toNumber(layout.itemSpacing, 0);
    node.paddingLeft = toNumber(layout.paddingLeft, 0);
    node.paddingRight = toNumber(layout.paddingRight, 0);
    node.paddingTop = toNumber(layout.paddingTop, 0);
    node.paddingBottom = toNumber(layout.paddingBottom, 0);
  }
}

async function applyText(textNode, def) {
  const fontName = await loadFontForText(def);
  textNode.fontName = fontName;
  textNode.characters = typeof def.characters === "string" ? def.characters : "";
  if (typeof def.fontSize === "number") textNode.fontSize = def.fontSize;
  if (def.textAlignHorizontal) textNode.textAlignHorizontal = def.textAlignHorizontal;
  if (def.textAlignVertical) textNode.textAlignVertical = def.textAlignVertical;
  if (typeof def.lineHeightPx === "number") {
    textNode.lineHeight = { value: def.lineHeightPx, unit: "PIXELS" };
  }
}

function createNodeByType(def) {
  switch (def.type) {
    case "FRAME":
      return figma.createFrame();
    case "RECTANGLE":
      return figma.createRectangle();
    case "TEXT":
      return figma.createText();
    case "ELLIPSE":
      return figma.createEllipse();
    case "BUTTON":
      return figma.createFrame();
    default:
      throw new Error(`不支持的节点类型: ${def.type}`);
  }
}

function ensureParent(node, parent, indexInParent) {
  if (node.parent !== parent) {
    parent.appendChild(node);
  }
  if (typeof indexInParent === "number" && hasChildren(parent)) {
    const currentIndex = parent.children.indexOf(node);
    if (currentIndex !== indexInParent) {
      parent.insertChild(indexInParent, node);
    }
  }
}

async function upsertNode(def, parent, idIndex, touched, options) {
  let node = idIndex.get(def.id);
  if (!node) {
    node = createNodeByType(def);
    idIndex.set(def.id, node);
  }

  node.setPluginData(PLUGIN_DATA_KEY_ID, def.id);
  node.setPluginData(PLUGIN_DATA_KEY_MANAGED, "1");
  touched.add(def.id);

  ensureParent(node, parent, options.indexInParent);

  if (def.type === "BUTTON") {
    def.layout = def.layout || {};
    def.layout.mode = "HORIZONTAL";
    def.layout.primaryAxisAlignItems = "CENTER";
    def.layout.counterAxisAlignItems = "CENTER";
    def.layout.primaryAxisSizingMode = "FIXED";
    def.layout.counterAxisSizingMode = "FIXED";
  }

  applyGeometry(node, def);
  applyCommonVisual(node, def);

  if (def.type === "FRAME" || def.type === "BUTTON") {
    applyAutoLayout(node, def);
  }

  if (def.type === "TEXT") {
    await applyText(node, def);
  }

  if (def.type === "BUTTON") {
    const labelId = `${def.id}__label`;
    const labelDef = {
      id: labelId,
      name: `${def.name}-label`,
      type: "TEXT",
      size: { width: toNumber(def.size?.width, 120), height: toNumber(def.size?.height, 20) },
      position: { x: 0, y: 0 },
      characters: def.characters || def.label || "Button",
      fontFamily: def.fontFamily || "Inter",
      fontStyle: def.fontStyle || "Medium",
      fontWeight: def.fontWeight || 500,
      fontSize: toNumber(def.fontSize, 16),
      fills: def.textFills || ["#FFFFFF"],
      textAlignHorizontal: "CENTER",
      textAlignVertical: "CENTER"
    };
    await upsertNode(labelDef, node, idIndex, touched, { indexInParent: 0, pruneMissing: options.pruneMissing });
  } else if (Array.isArray(def.children) && hasChildren(node)) {
    for (let i = 0; i < def.children.length; i += 1) {
      await upsertNode(def.children[i], node, idIndex, touched, {
        indexInParent: i,
        pruneMissing: options.pruneMissing
      });
    }
  }

  if (options.pruneMissing && hasChildren(node)) {
    const shouldKeep = new Set((def.children || []).map((child) => child.id));
    if (def.type === "BUTTON") shouldKeep.add(`${def.id}__label`);
    for (const child of [...node.children]) {
      const childId = child.getPluginData(PLUGIN_DATA_KEY_ID);
      if (isManaged(child) && childId && !shouldKeep.has(childId)) {
        child.remove();
        idIndex.delete(childId);
      }
    }
  }

  return node;
}

function pruneDetached(idIndex, touched) {
  for (const [id, node] of idIndex.entries()) {
    if (!touched.has(id) && isManaged(node)) {
      node.remove();
      idIndex.delete(id);
    }
  }
}

async function applySchema(schema, options) {
  const idIndex = buildIdIndex();
  const touched = new Set();
  const roots = [];
  for (let i = 0; i < schema.frames.length; i += 1) {
    const frameDef = schema.frames[i];
    const frame = await upsertNode(frameDef, figma.currentPage, idIndex, touched, {
      indexInParent: i,
      pruneMissing: options.pruneMissing
    });
    roots.push(frame);
  }

  if (options.pruneMissing) {
    pruneDetached(idIndex, touched);
  }

  figma.currentPage.selection = roots;
  if (roots.length > 0) {
    figma.viewport.scrollAndZoomIntoView(roots);
  }
}

figma.ui.onmessage = async (msg) => {
  if (!msg || typeof msg !== "object") return;

  if (msg.type === "validate") {
    try {
      const schema = JSON.parse(msg.payload || "{}");
      const errors = validateSchema(schema);
      post("validated", { ok: errors.length === 0, errors });
    } catch (error) {
      post("validated", { ok: false, errors: [String(error.message || error)] });
    }
    return;
  }

  if (msg.type === "apply") {
    try {
      const schema = JSON.parse(msg.payload || "{}");
      const errors = validateSchema(schema);
      if (errors.length > 0) {
        post("applied", { ok: false, message: "schema 校验失败", errors });
        return;
      }
      await applySchema(schema, { pruneMissing: msg.pruneMissing === true });
      post("applied", {
        ok: true,
        message: `已同步 ${schema.frames.length} 个顶层 Frame 到当前页面`
      });
    } catch (error) {
      post("applied", { ok: false, message: String(error.message || error), errors: [] });
    }
    return;
  }

  if (msg.type === "close") {
    figma.closePlugin("Tsugie UI Schema Bridge 结束");
  }
};
