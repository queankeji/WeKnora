/** 帮助文档站点根地址。
 *
 * 都会美家知识库：内部文档站就绪后在此常量填入地址（单点修改）。
 * 当前未部署文档站，链接指向站内相对路径，点击时由前端兜底提示，
 * 不再引用任何外部厂商文档（去品牌化）。
 */
export const DOCS_BASE_URL = '/docs/'

/**
 * Doc pages linked from the UI, as website-docs paths without the `.md`
 * suffix. docsUrl.test.ts checks each one (and its anchor) still exists.
 */
export const DOC_PAGES = {
  home: '',
  tenantAuth: '03-features/01-tenant-auth',
  models: '03-features/06-models',
  modelsCompat: '03-features/06-models#协议兼容覆盖-compat-json',
  knowledgeGraph: '03-features/09-knowledge-graph',
  imIntegration: '03-features/12-im-integration',
  apiOverview: '04-api/01-api-overview',
  troubleshootingMigrations: '01-getting-started/05-troubleshooting#database-migrations',
  sandboxDeployment: '06-development/04-sandbox-deployment',
} as const

export type DocPage = keyof typeof DOC_PAGES

export function docsUrl(page: DocPage): string {
  return DOCS_BASE_URL + DOC_PAGES[page]
}
