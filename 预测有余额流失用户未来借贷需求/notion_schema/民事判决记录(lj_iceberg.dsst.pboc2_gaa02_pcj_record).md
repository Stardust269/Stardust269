# 民事判决记录(lj_iceberg.dsst.pboc2_gaa02_pcj_record)
page_id: 39c617cf-3593-8059-b1bf-dbfd7b19b84e


| 数值类型 | 字段解释 | 字段编码 | 备注 | 字段名称 |
| long | 自增主键ID | id |  | 主键ID |
| varchar(32) | 报告ID | id_unqf |  | 报告ID |
| varchar(32) | 客户ID | id_unqp |  | 客户ID |
| varchar(64) | 立案法院 | court_file |  | 立案法院 |
| varchar(256) | 判决案由 | reason |  | 案由 |
| date | 立案日期 | date_file_case |  | 立案日期 |
| varchar(16) | 结案方式 | type_close_way | 对应字典：force_execute_code | 结案方式 |
| varchar(256) | 判决/调解结果 | result |  | 判决/调解结果 |
| date | 判决/调解生效日期 | efffect_date |  | 判决/调解生效日期 |
| varchar(16) | 诉讼标的 | sub_litigation |  | 诉讼标的 |
| int | 诉讼标的金额 | sub_litigation_amount |  | 诉讼标的金额 |
| datetime | 系统插入时间 | time_inst |  | 系统插入时间 |