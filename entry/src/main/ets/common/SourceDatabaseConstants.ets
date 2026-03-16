/**
 * 数据源数据库常量定义
 */
export class SourceDatabaseConstants {
  /**
   * 数据库名称
   */
  static readonly DATABASE_NAME: string = 'source_config.db';

  /**
   * 数据库版本
   */
  static readonly DATABASE_VERSION: number = 1;

  /**
   * 数据库安全级别
   */
  static readonly SECURITY_LEVEL: number = 3; // S3 级别

  /**
   * 数据源表名
   */
  static readonly TABLE_SOURCES: string = 'sources';

  /**
   * 创建数据源表的 SQL 语句
   */
  static readonly CREATE_TABLE_SOURCES: string = `
    CREATE TABLE IF NOT EXISTS sources (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      url TEXT NOT NULL,
      description TEXT,
      token TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `;

  /**
   * 创建索引的 SQL 语句
   */
  static readonly CREATE_INDEX_CREATED_AT: string = `
    CREATE INDEX IF NOT EXISTS idx_sources_created_at
    ON sources(created_at DESC)
  `;

  /**
   * 创建类型索引的 SQL 语句
   */
  static readonly CREATE_INDEX_TYPE: string = `
    CREATE INDEX IF NOT EXISTS idx_sources_type
    ON sources(type)
  `;

  /**
   * sources 表字段名称
   */
  static readonly COLUMN_ID: string = 'id';
  static readonly COLUMN_NAME: string = 'name';
  static readonly COLUMN_TYPE: string = 'type';
  static readonly COLUMN_URL: string = 'url';
  static readonly COLUMN_DESCRIPTION: string = 'description';
  static readonly COLUMN_TOKEN: string = 'token';
  static readonly COLUMN_CREATED_AT: string = 'created_at';
  static readonly COLUMN_UPDATED_AT: string = 'updated_at';
}

