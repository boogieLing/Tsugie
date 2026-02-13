#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const SUPPORTED_TYPES = new Set([
  "FRAME",
  "GROUP",
  "COMPONENT",
  "SECTION",
  "RECTANGLE",
  "ELLIPSE",
  "LINE",
  "POLYGON",
  "STAR",
  "VECTOR",
  "TEXT",
  "SLICE",
  "INSTANCE",
  "BUTTON"
]);

function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exit(1);
}

function rootsFromSchema(schema) {
  if (Array.isArray(schema.frames) && schema.frames.length > 0) return schema.frames;
  if (Array.isArray(schema.nodes) && schema.nodes.length > 0) return schema.nodes;
  return [];
}

function walk(node, pointer, idSet, errors) {
  if (typeof node !== "object" || node === null) {
    errors.push(`${pointer} must be an object`);
    return;
  }

  if (typeof node.id !== "string" || node.id.trim() === "") {
    errors.push(`${pointer}.id must be a non-empty string`);
  } else if (idSet.has(node.id)) {
    errors.push(`${pointer}.id duplicated: ${node.id}`);
  } else {
    idSet.add(node.id);
  }

  if (typeof node.name !== "string" || node.name.trim() === "") {
    errors.push(`${pointer}.name must be a non-empty string`);
  }

  if (typeof node.type !== "string" || !SUPPORTED_TYPES.has(node.type)) {
    errors.push(`${pointer}.type unsupported: ${node.type}`);
  }

  if (!node.size || typeof node.size.width !== "number" || typeof node.size.height !== "number") {
    errors.push(`${pointer}.size.width/height must be numbers`);
  }

  if (node.type === "INSTANCE" && !node.componentId && !node.componentKey) {
    errors.push(`${pointer} (INSTANCE) requires componentId or componentKey`);
  }

  if (node.children !== undefined && !Array.isArray(node.children)) {
    errors.push(`${pointer}.children must be an array`);
  }

  if (Array.isArray(node.children)) {
    node.children.forEach((child, idx) => walk(child, `${pointer}.children[${idx}]`, idSet, errors));
  }
}

function validate(schema) {
  const errors = [];
  if (!schema || typeof schema !== "object") {
    errors.push("schema must be an object");
    return errors;
  }
  if (schema.version !== "1.0") {
    errors.push('schema.version must be "1.0"');
  }

  const roots = rootsFromSchema(schema);
  if (roots.length === 0) {
    errors.push("schema.frames or schema.nodes must be a non-empty array");
    return errors;
  }

  const idSet = new Set();
  roots.forEach((node, idx) => walk(node, `roots[${idx}]`, idSet, errors));
  return errors;
}

const inputPath = process.argv[2];
if (!inputPath) {
  fail("usage: node scripts/validate-ui-schema.js <schema-json-path>");
}

const resolved = path.resolve(process.cwd(), inputPath);
if (!fs.existsSync(resolved)) {
  fail(`file not found: ${resolved}`);
}

let schema;
try {
  schema = JSON.parse(fs.readFileSync(resolved, "utf8"));
} catch (err) {
  fail(`invalid JSON: ${err.message}`);
}

const errors = validate(schema);
if (errors.length > 0) {
  console.error("Schema validation failed:");
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log("Schema validation passed.");
