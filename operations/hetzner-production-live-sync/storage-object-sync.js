'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const {execFile} = require('child_process');
const {pipeline} = require('stream/promises');
const {promisify} = require('util');

const execFileAsync = promisify(execFile);

const manifestPath = process.env.STORAGE_SYNC_MANIFEST;
const storageRoot = process.env.STORAGE_SYNC_TARGET_ROOT;
const sourceUrl = process.env.HOSTED_SUPABASE_URL;
const sourceServiceKey = process.env.HOSTED_SUPABASE_SERVICE_ROLE_KEY;
const statusPath = process.env.STORAGE_SYNC_STATUS;
const concurrency = Number.parseInt(process.env.STORAGE_SYNC_CONCURRENCY || '4', 10);

for (const [name, value] of Object.entries({manifestPath, storageRoot, sourceUrl, sourceServiceKey, statusPath})) {
  if (!value) {
    throw new Error(`Missing required environment variable for ${name}`);
  }
}

function resolveObjectPath(object) {
  const relativeParts = ['stub', 'stub', object.bucket_id, ...object.name.split('/')];
  if (object.version) {
    relativeParts.push(object.version);
  }

  const destinationPath = path.resolve(storageRoot, ...relativeParts);
  const allowedRoot = `${path.resolve(storageRoot, 'stub', 'stub')}${path.sep}`;
  if (!destinationPath.startsWith(allowedRoot)) {
    throw new Error(`Unsafe storage object path: ${object.bucket_id}/${object.name}`);
  }

  return destinationPath;
}

function sourceObjectUrl(object) {
  const encodedPath = [object.bucket_id, ...object.name.split('/')].map(encodeURIComponent).join('/');
  return `${sourceUrl.replace(/\/$/, '')}/storage/v1/object/authenticated/${encodedPath}`;
}

async function calculateMd5(filePath) {
  const hash = crypto.createHash('md5');
  await pipeline(fs.createReadStream(filePath), hash);
  return hash.digest('hex');
}

async function setObjectMetadata(filePath, object) {
  await execFileAsync('setfattr', ['-n', 'user.supabase.content-type', '-v', object.mimetype || 'application/octet-stream', filePath]);
  await execFileAsync('setfattr', ['-n', 'user.supabase.cache-control', '-v', object.cache_control || 'no-cache', filePath]);
}

async function syncObject(object) {
  const destinationPath = resolveObjectPath(object);
  const expectedSize = Number(object.size || 0);

  try {
    const existingStat = await fs.promises.stat(destinationPath);
    if (existingStat.isFile() && existingStat.size === expectedSize) {
      await setObjectMetadata(destinationPath, object);
      return {downloaded: false, bytes: 0, md5: await calculateMd5(destinationPath)};
    }
  } catch (error) {
    if (error.code !== 'ENOENT') {
      throw error;
    }
  }

  await fs.promises.mkdir(path.dirname(destinationPath), {recursive: true});
  const temporaryPath = `${destinationPath}.partial-${process.pid}`;
  const response = await fetch(sourceObjectUrl(object), {
    headers: {
      apikey: sourceServiceKey,
      Authorization: `Bearer ${sourceServiceKey}`,
    },
  });

  if (!response.ok || !response.body) {
    throw new Error(`Storage download failed (${response.status}) for ${object.bucket_id}/${object.name}`);
  }

  try {
    await pipeline(response.body, fs.createWriteStream(temporaryPath, {mode: 0o640}));
    const downloadedStat = await fs.promises.stat(temporaryPath);
    if (downloadedStat.size !== expectedSize) {
      throw new Error(`Storage size mismatch for ${object.bucket_id}/${object.name}: expected ${expectedSize}, got ${downloadedStat.size}`);
    }
    await setObjectMetadata(temporaryPath, object);
    await fs.promises.rename(temporaryPath, destinationPath);
    return {downloaded: true, bytes: downloadedStat.size, md5: await calculateMd5(destinationPath)};
  } catch (error) {
    await fs.promises.rm(temporaryPath, {force: true});
    throw error;
  }
}

async function runPool(objects) {
  const results = [];
  let nextIndex = 0;

  async function worker() {
    while (nextIndex < objects.length) {
      const object = objects[nextIndex];
      nextIndex += 1;
      try {
        const result = await syncObject(object);
        results.push({...result, id: object.id, bucket_id: object.bucket_id, name: object.name, version: object.version});
      } catch (error) {
        results.push({id: object.id, bucket_id: object.bucket_id, name: object.name, version: object.version, error: error.message});
      }
    }
  }

  await Promise.all(Array.from({length: Math.max(1, concurrency)}, worker));
  return results;
}

async function main() {
  const manifest = await fs.promises.readFile(manifestPath, 'utf8');
  const objects = manifest.split('\n').filter(Boolean).map((line) => JSON.parse(line));
  const startedAt = new Date().toISOString();
  const results = await runPool(objects);
  const failures = results.filter((result) => result.error);
  const downloaded = results.filter((result) => result.downloaded);
  const status = {
    started_at: startedAt,
    completed_at: new Date().toISOString(),
    manifest_objects: objects.length,
    synchronized_objects: results.length - failures.length,
    downloaded_objects: downloaded.length,
    downloaded_bytes: downloaded.reduce((total, result) => total + result.bytes, 0),
    failures: failures.map(({bucket_id, name, version, error}) => ({bucket_id, name, version, error})),
  };

  const temporaryStatusPath = `${statusPath}.tmp`;
  await fs.promises.writeFile(temporaryStatusPath, `${JSON.stringify(status, null, 2)}\n`, {mode: 0o600});
  await fs.promises.rename(temporaryStatusPath, statusPath);
  process.stdout.write(`${JSON.stringify(status)}\n`);

  if (failures.length > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

