'use strict';

const fs = require('fs');
const path = require('path');

const STATE_VERSION = 1;
const DELETE_BATCH_SIZE = 1000;

function objectKey(object) {
  return JSON.stringify([object.bucket_id, object.name]);
}

function objectFingerprint(object) {
  return JSON.stringify({
    version: object.version,
    size: Number(object.size || 0),
    etag: object.etag || null,
    mimetype: object.mimetype || null,
    cache_control: object.cache_control || null,
    user_metadata: object.user_metadata || {},
  });
}

function bucketFingerprint(bucket) {
  return JSON.stringify({
    public: Boolean(bucket.public),
    file_size_limit: bucket.file_size_limit ?? null,
    allowed_mime_types: bucket.allowed_mime_types ?? null,
  });
}

function resolveObjectPath(storageRoot, object) {
  const relativeParts = ['stub', 'stub', object.bucket_id, ...object.name.split('/')];
  if (object.version) relativeParts.push(object.version);

  const sourcePath = path.resolve(storageRoot, ...relativeParts);
  const allowedRoot = `${path.resolve(storageRoot, 'stub', 'stub')}${path.sep}`;
  if (!sourcePath.startsWith(allowedRoot)) {
    throw new Error(`Unsafe storage object path: ${object.bucket_id}/${object.name}`);
  }
  return sourcePath;
}

function apiHeaders(serviceKey, extra = {}) {
  return {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    ...extra,
  };
}

async function assertApiResponse(response, description) {
  if (response.ok) return;
  const responseText = (await response.text()).slice(0, 500);
  throw new Error(`${description} failed (${response.status}): ${responseText}`);
}

async function createOrUpdateBucket({ cloudUrl, serviceKey, bucket, create, fetchImpl = fetch }) {
  const endpoint = create
    ? `${cloudUrl.replace(/\/$/, '')}/storage/v1/bucket`
    : `${cloudUrl.replace(/\/$/, '')}/storage/v1/bucket/${encodeURIComponent(bucket.id)}`;
  const response = await fetchImpl(endpoint, {
    method: create ? 'POST' : 'PUT',
    headers: apiHeaders(serviceKey, { 'content-type': 'application/json' }),
    body: JSON.stringify({
      id: bucket.id,
      name: bucket.id,
      public: Boolean(bucket.public),
      file_size_limit: bucket.file_size_limit ?? null,
      allowed_mime_types: bucket.allowed_mime_types ?? null,
    }),
  });
  await assertApiResponse(response, `${create ? 'create' : 'update'} bucket ${bucket.id}`);
}

async function deleteBucket({ cloudUrl, serviceKey, bucketId, fetchImpl = fetch }) {
  const response = await fetchImpl(`${cloudUrl.replace(/\/$/, '')}/storage/v1/bucket/${encodeURIComponent(bucketId)}`, {
    method: 'DELETE',
    headers: apiHeaders(serviceKey, { 'content-type': 'application/json' }),
    body: '{}',
  });
  await assertApiResponse(response, `delete bucket ${bucketId}`);
}

async function uploadObject({ cloudUrl, serviceKey, storageRoot, object, fetchImpl = fetch }) {
  const sourcePath = resolveObjectPath(storageRoot, object);
  const sourceStat = await fs.promises.stat(sourcePath);
  const expectedSize = Number(object.size || 0);
  if (!sourceStat.isFile() || sourceStat.size !== expectedSize) {
    throw new Error(`Source size mismatch for ${object.bucket_id}/${object.name}: expected ${expectedSize}, got ${sourceStat.size}`);
  }

  const encodedPath = [object.bucket_id, ...object.name.split('/')].map(encodeURIComponent).join('/');
  const response = await fetchImpl(`${cloudUrl.replace(/\/$/, '')}/storage/v1/object/${encodedPath}`, {
    method: 'POST',
    headers: apiHeaders(serviceKey, {
      'cache-control': `max-age=${object.cache_control || 'no-cache'}`,
      'content-length': String(sourceStat.size),
      'content-type': object.mimetype || 'application/octet-stream',
      'x-metadata': Buffer.from(JSON.stringify(object.user_metadata || {})).toString('base64'),
      'x-upsert': 'true',
    }),
    body: fs.createReadStream(sourcePath),
    duplex: 'half',
  });
  await assertApiResponse(response, `upload object ${object.bucket_id}/${object.name}`);
  return sourceStat.size;
}

async function deleteObjectBatch({ cloudUrl, serviceKey, bucketId, paths, fetchImpl = fetch }) {
  const response = await fetchImpl(`${cloudUrl.replace(/\/$/, '')}/storage/v1/object/${encodeURIComponent(bucketId)}`, {
    method: 'DELETE',
    headers: apiHeaders(serviceKey, { 'content-type': 'application/json' }),
    body: JSON.stringify({ prefixes: paths }),
  });
  await assertApiResponse(response, `delete ${paths.length} object(s) from bucket ${bucketId}`);
}

async function readJson(filePath, fallback) {
  try {
    return JSON.parse(await fs.promises.readFile(filePath, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return fallback;
    throw error;
  }
}

async function writeJsonAtomic(filePath, value) {
  const temporaryPath = `${filePath}.tmp`;
  await fs.promises.writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  await fs.promises.rename(temporaryPath, filePath);
}

async function runPool(items, concurrency, operation) {
  const results = [];
  let nextIndex = 0;

  async function worker() {
    while (nextIndex < items.length) {
      const item = items[nextIndex];
      nextIndex += 1;
      try {
        results.push({ item, value: await operation(item) });
      } catch (error) {
        results.push({ item, error: error.message });
      }
    }
  }

  await Promise.all(Array.from({ length: Math.max(1, concurrency) }, worker));
  return results;
}

async function synchronizeBuckets(configuration, buckets, previousBuckets) {
  const currentById = new Map(buckets.map((bucket) => [bucket.id, bucket]));
  const changedBuckets = buckets.filter((bucket) => previousBuckets[bucket.id] !== bucketFingerprint(bucket));
  const removedBucketIds = Object.keys(previousBuckets).filter((bucketId) => !currentById.has(bucketId));
  const changedResults = await runPool(changedBuckets, configuration.concurrency, async (bucket) => {
    await createOrUpdateBucket({
      ...configuration,
      bucket,
      create: previousBuckets[bucket.id] === undefined,
    });
    return bucketFingerprint(bucket);
  });
  return { currentById, changedResults, removedBucketIds };
}

async function synchronizeObjects(configuration, objects, previousObjects) {
  const currentByKey = new Map(objects.map((object) => [objectKey(object), object]));
  const changedObjects = objects.filter((object) => previousObjects[objectKey(object)]?.fingerprint !== objectFingerprint(object));
  const removedObjects = Object.entries(previousObjects)
    .filter(([key]) => !currentByKey.has(key))
    .map(([key, value]) => ({ key, ...value }));
  const uploadResults = await runPool(changedObjects, configuration.concurrency, async (object) => ({
    bytes: await uploadObject({ ...configuration, object }),
    fingerprint: objectFingerprint(object),
    bucket_id: object.bucket_id,
    name: object.name,
  }));

  const removedByBucket = new Map();
  for (const object of removedObjects) {
    if (!removedByBucket.has(object.bucket_id)) removedByBucket.set(object.bucket_id, []);
    removedByBucket.get(object.bucket_id).push(object);
  }
  const deleteBatches = [];
  for (const [bucketId, bucketObjects] of removedByBucket) {
    for (let index = 0; index < bucketObjects.length; index += DELETE_BATCH_SIZE) {
      deleteBatches.push({ bucketId, objects: bucketObjects.slice(index, index + DELETE_BATCH_SIZE) });
    }
  }
  const deleteResults = await runPool(deleteBatches, configuration.concurrency, async (batch) => {
    await deleteObjectBatch({ ...configuration, bucketId: batch.bucketId, paths: batch.objects.map((object) => object.name) });
    return batch.objects.map((object) => object.key);
  });

  return { currentByKey, uploadResults, deleteResults };
}

async function main() {
  const manifestPath = process.env.STORAGE_STANDBY_MANIFEST;
  const bucketManifestPath = process.env.STORAGE_STANDBY_BUCKET_MANIFEST;
  const statePath = process.env.STORAGE_STANDBY_STATE;
  const statusPath = process.env.STORAGE_STANDBY_STATUS;
  const storageRoot = process.env.STORAGE_STANDBY_SOURCE_ROOT;
  const cloudUrl = process.env.HOSTED_SUPABASE_URL;
  const serviceKey = process.env.HOSTED_SUPABASE_SERVICE_ROLE_KEY;
  const mode = process.env.STORAGE_STANDBY_MODE;
  const concurrency = Number.parseInt(process.env.STORAGE_STANDBY_CONCURRENCY || '2', 10);

  for (const [name, value] of Object.entries({ manifestPath, bucketManifestPath, statePath, statusPath, storageRoot, cloudUrl, serviceKey, mode })) {
    if (!value) throw new Error(`Missing required environment variable for ${name}`);
  }
  if (!['seed', 'sync'].includes(mode)) throw new Error(`Unsupported Storage standby mode: ${mode}`);
  if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 32) throw new Error(`Invalid Storage standby concurrency: ${concurrency}`);

  const objectManifest = await fs.promises.readFile(manifestPath, 'utf8');
  const bucketManifest = await fs.promises.readFile(bucketManifestPath, 'utf8');
  const objects = objectManifest.split('\n').filter(Boolean).map((line) => JSON.parse(line));
  const buckets = bucketManifest.split('\n').filter(Boolean).map((line) => JSON.parse(line));
  const previousState = await readJson(statePath, { version: STATE_VERSION, objects: {}, buckets: {} });
  if (previousState.version !== STATE_VERSION) throw new Error(`Unsupported Storage standby state version: ${previousState.version}`);
  const startedAt = new Date().toISOString();

  if (mode === 'seed') {
    const state = {
      version: STATE_VERSION,
      updated_at: new Date().toISOString(),
      objects: Object.fromEntries(objects.map((object) => [objectKey(object), {
        fingerprint: objectFingerprint(object),
        bucket_id: object.bucket_id,
        name: object.name,
      }])),
      buckets: Object.fromEntries(buckets.map((bucket) => [bucket.id, bucketFingerprint(bucket)])),
    };
    const status = {
      mode,
      started_at: startedAt,
      completed_at: new Date().toISOString(),
      manifest_objects: objects.length,
      manifest_buckets: buckets.length,
      uploaded_objects: 0,
      deleted_objects: 0,
      changed_buckets: 0,
      deleted_buckets: 0,
      failures: [],
    };
    await writeJsonAtomic(statePath, state);
    await writeJsonAtomic(statusPath, status);
    process.stdout.write(`${JSON.stringify(status)}\n`);
    return;
  }

  const configuration = { cloudUrl, serviceKey, storageRoot, concurrency };
  const bucketSync = await synchronizeBuckets(configuration, buckets, previousState.buckets || {});
  const objectSync = await synchronizeObjects(configuration, objects, previousState.objects || {});
  const bucketFailures = bucketSync.changedResults.filter((result) => result.error);
  const uploadFailures = objectSync.uploadResults.filter((result) => result.error);
  const deleteFailures = objectSync.deleteResults.filter((result) => result.error);

  const removedObjectKeys = new Set(objectSync.deleteResults.filter((result) => !result.error).flatMap((result) => result.value));
  const nextObjects = { ...(previousState.objects || {}) };
  for (const key of removedObjectKeys) delete nextObjects[key];
  for (const result of objectSync.uploadResults) {
    if (!result.error) nextObjects[objectKey(result.item)] = result.value;
  }

  const nextBuckets = { ...(previousState.buckets || {}) };
  for (const result of bucketSync.changedResults) {
    if (!result.error) nextBuckets[result.item.id] = result.value;
  }

  const removableBucketIds = bucketSync.removedBucketIds.filter((bucketId) => !Object.values(nextObjects).some((object) => object.bucket_id === bucketId));
  const bucketDeleteResults = await runPool(removableBucketIds, concurrency, async (bucketId) => {
    await deleteBucket({ ...configuration, bucketId });
    return bucketId;
  });
  for (const result of bucketDeleteResults) {
    if (!result.error) delete nextBuckets[result.item];
  }

  const failures = [
    ...bucketFailures.map((result) => ({ operation: 'bucket-upsert', key: result.item.id, error: result.error })),
    ...uploadFailures.map((result) => ({ operation: 'object-upload', key: objectKey(result.item), error: result.error })),
    ...deleteFailures.map((result) => ({ operation: 'object-delete', key: result.item.bucketId, error: result.error })),
    ...bucketDeleteResults.filter((result) => result.error).map((result) => ({ operation: 'bucket-delete', key: result.item, error: result.error })),
  ];
  const uploaded = objectSync.uploadResults.filter((result) => !result.error);
  const deletedObjects = objectSync.deleteResults.filter((result) => !result.error).reduce((total, result) => total + result.value.length, 0);
  const status = {
    mode,
    started_at: startedAt,
    completed_at: new Date().toISOString(),
    manifest_objects: objects.length,
    manifest_buckets: buckets.length,
    uploaded_objects: uploaded.length,
    uploaded_bytes: uploaded.reduce((total, result) => total + result.value.bytes, 0),
    deleted_objects: deletedObjects,
    changed_buckets: bucketSync.changedResults.length - bucketFailures.length,
    deleted_buckets: bucketDeleteResults.filter((result) => !result.error).length,
    failures,
  };
  await writeJsonAtomic(statePath, { version: STATE_VERSION, updated_at: new Date().toISOString(), objects: nextObjects, buckets: nextBuckets });
  await writeJsonAtomic(statusPath, status);
  process.stdout.write(`${JSON.stringify(status)}\n`);
  if (failures.length > 0) process.exitCode = 1;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}

module.exports = {
  bucketFingerprint,
  createOrUpdateBucket,
  deleteObjectBatch,
  objectFingerprint,
  objectKey,
  resolveObjectPath,
};
