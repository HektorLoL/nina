export type NinaChatRequest = {
  family_id: string;
  message_id?: string;
  message: string;
  attachments?: NinaChatAttachment[];
};

export type NinaChatAttachment = {
  kind: "image" | "document";
  filename: string;
  mime_type: string;
  data_base64: string;
};

export const maxAttachmentCount = 3;
export const maxAttachmentBytes = 5 * 1024 * 1024;
export const maxTotalAttachmentBytes = 8 * 1024 * 1024;

const base64Pattern = /^[A-Za-z0-9+/]*={0,2}$/;
const imageMimeTypes = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
]);
const documentMimeTypes = new Set([
  "application/pdf",
  "application/msword",
  "application/rtf",
  "application/json",
  "application/vnd.apple.iwork",
  "application/vnd.apple.pages",
  "application/vnd.ms-excel",
  "application/vnd.ms-powerpoint",
  "application/vnd.oasis.opendocument.text",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "text/csv",
  "text/html",
  "text/markdown",
  "text/plain",
  "text/rtf",
  "text/tab-separated-values",
  "text/tsv",
  "text/xml",
]);

export function isNinaChatRequest(value: unknown): value is NinaChatRequest {
  if (!value || typeof value !== "object") return false;

  const request = value as Partial<NinaChatRequest>;
  const attachments = request.attachments ?? [];
  let totalBytes = 0;

  if (
    !Array.isArray(attachments)
    || attachments.length > maxAttachmentCount
    || !attachments.every((attachment) => {
      if (!attachment || typeof attachment !== "object") return false;

      if (
        (attachment.kind !== "image" && attachment.kind !== "document")
        || typeof attachment.filename !== "string"
        || attachment.filename.trim().length === 0
        || attachment.filename.length > 180
        || typeof attachment.mime_type !== "string"
        || typeof attachment.data_base64 !== "string"
        || attachment.data_base64.length === 0
        || attachment.data_base64.length % 4 !== 0
        || !base64Pattern.test(attachment.data_base64)
      ) {
        return false;
      }

      const estimatedBytes = Math.floor(attachment.data_base64.length * 0.75);
      const allowedMimeTypes = attachment.kind === "image"
        ? imageMimeTypes
        : documentMimeTypes;
      totalBytes += estimatedBytes;

      return allowedMimeTypes.has(attachment.mime_type)
        && estimatedBytes <= maxAttachmentBytes;
    })
    || totalBytes > maxTotalAttachmentBytes
  ) {
    return false;
  }

  return typeof request.family_id === "string"
    && /^[0-9a-f-]{36}$/i.test(request.family_id)
    && (
      request.message_id === undefined
      || (
        typeof request.message_id === "string"
        && /^[0-9a-f-]{36}$/i.test(request.message_id)
      )
    )
    && typeof request.message === "string"
    && request.message.length <= 2000
    && (request.message.trim().length > 0 || attachments.length > 0);
}

export function attachmentMetadata(
  attachments: NinaChatAttachment[],
): Array<Record<string, unknown>> {
  return attachments.map((attachment) => ({
    kind: attachment.kind,
    filename: attachment.filename,
    mime_type: attachment.mime_type,
    byte_count: Math.floor(attachment.data_base64.length * 0.75),
  }));
}
