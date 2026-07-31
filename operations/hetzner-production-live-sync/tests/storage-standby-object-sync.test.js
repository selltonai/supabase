'use strict';

const assert = require('assert');
const path = require('path');
const {
  bucketFingerprint,
  createOrUpdateBucket,
  deleteObjectBatch,
  objectFingerprint,
  objectKey,
  resolveObjectPath,
} = require('../storage-standby-object-sync');

function response(ok = true, status = 200, body = '') {
  return { ok, status, text: async () => body };
}

async function testBucketUpsertRequest() {
  const requests = [];
  await createOrUpdateBucket({
    cloudUrl: 'https://cloud.example.test/',
    serviceKey: 'secret',
    bucket: { id: 'documents', public: false, file_size_limit: 1000, allowed_mime_types: ['application/pdf'] },
    create: true,
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      return response();
    },
  });

  assert.strictEqual(requests.length, 1);
  assert.strictEqual(requests[0].url, 'https://cloud.example.test/storage/v1/bucket');
  assert.strictEqual(requests[0].options.method, 'POST');
  assert.deepStrictEqual(JSON.parse(requests[0].options.body), {
    id: 'documents',
    name: 'documents',
    public: false,
    file_size_limit: 1000,
    allowed_mime_types: ['application/pdf'],
  });
  assert.strictEqual(requests[0].options.headers.apikey, 'secret');
}

async function testObjectDeleteRequest() {
  const requests = [];
  await deleteObjectBatch({
    cloudUrl: 'https://cloud.example.test',
    serviceKey: 'secret',
    bucketId: 'documents',
    paths: ['folder/one.pdf', 'two.pdf'],
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      return response();
    },
  });

  assert.strictEqual(requests[0].url, 'https://cloud.example.test/storage/v1/object/documents');
  assert.strictEqual(requests[0].options.method, 'DELETE');
  assert.deepStrictEqual(JSON.parse(requests[0].options.body), { prefixes: ['folder/one.pdf', 'two.pdf'] });
}

function testStableStateKeysAndFingerprints() {
  const object = {
    bucket_id: 'documents',
    name: 'folder/report.pdf',
    version: 'v1',
    size: 42,
    etag: 'etag',
    mimetype: 'application/pdf',
    cache_control: '3600',
    user_metadata: { owner: 'user-1' },
  };
  assert.strictEqual(objectKey(object), '["documents","folder/report.pdf"]');
  assert.strictEqual(objectFingerprint(object), objectFingerprint({ ...object }));
  assert.notStrictEqual(objectFingerprint(object), objectFingerprint({ ...object, size: 43 }));
  assert.strictEqual(bucketFingerprint({ id: 'documents', public: false }), bucketFingerprint({ id: 'documents', public: false }));
}

function testObjectPathGuard() {
  const root = '/srv/storage';
  assert.strictEqual(
    resolveObjectPath(root, { bucket_id: 'documents', name: 'folder/report.pdf', version: 'v1' }),
    path.resolve(root, 'stub', 'stub', 'documents', 'folder', 'report.pdf', 'v1'),
  );
  assert.throws(() => resolveObjectPath(root, { bucket_id: 'documents', name: '../../../etc/passwd' }), /Unsafe storage object path/);
}

async function main() {
  await testBucketUpsertRequest();
  await testObjectDeleteRequest();
  testStableStateKeysAndFingerprints();
  testObjectPathGuard();
  console.log('Storage standby object sync tests passed');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
