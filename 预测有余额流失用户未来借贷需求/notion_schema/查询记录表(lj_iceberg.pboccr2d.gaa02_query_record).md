# 查询记录表(lj_iceberg.pboccr2d.gaa02_query_record)
page_id: 39c617cf-3593-8021-87b5-fb7111ec1209


| 数值类型 | 字段解释 | 字段名称 | 字段编码 | 备注 |
| long | 自增主键ID | 主键ID | id |  |
| varchar(32) | 报告ID | 报告ID | id_unqf |  |
| varchar(32) | 客户ID | 客户ID | id_unqp |  |
| date | 查询日期 | 查询日期 | query_date |  |
| varchar(32) | 查询机构 | 查询机构 | query_org |  |
| varchar(16) | 查询原因 | 查询原因 | query_reason | 对应字典表：query_reason_code |
| datetime | 插入时间 | 插入时间 | time_inst |  |