# 执业资格记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_ppq_record)
page_id: 39c617cf-3593-8056-9f88-c697522bfbde


| 字段解释 | 数值类型 | 字段编码 | 字段名称 | 备注 |
| 自增主键ID | long | id | 主键ID |  |
| 报告ID | varchar(32) | id_unqf | 报告ID |  |
| 客户ID | varchar(32) | id_unqp | 客户ID |  |
| 编号 | int | no_serial | 编号 |  |
| 执业资格名称 | varchar(64) | ppq_name | 执行资格名称 |  |
| 等级 | varchar(16) | level | 等级 | 对应字典表：professional_qualification_level_code |
| 获得日期 | date | acquire_date | 获得日期 |  |
| 到期日期 | date | expire_date | 到期日期 |  |
| 吊销日期 | date | revoke_date | 吊销日期 |  |
| 颁发机构 | varchar(32) | award_org | 颁发机构 |  |
| 机构所在地 | varchar(32) | org_location | 机构所在地 |  |
| 插入时间 | datetime | time_inst | 插入时间 |  |