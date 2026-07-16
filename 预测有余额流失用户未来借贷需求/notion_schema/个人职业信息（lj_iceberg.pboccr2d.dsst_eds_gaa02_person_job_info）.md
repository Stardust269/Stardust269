# 个人职业信息（lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info）
page_id: 39c617cf-3593-80eb-8315-c3f6b365e8ec


| 字段编码 | 字段名称 | 字段解释 | 数值类型 | 备注 |
| id | 唯一标识 | 自增主键 | long |  |
| id_unqf | 报告ID | 报告ID | varchar(32) |  |
| id_unqp | 客户ID | 客户ID | varchar(32) |  |
| job_state | 就业状态 | 就业状态 | varchar(8) | 对应字典：employment_state_code |
| company_name | 工作单位名称 | 工作单位名称 | varchar(128) |  |
| org_type | 单位性质 | 单位性质 | varchar(32) | 对应字典：org_type_code |
| company_address | 单位地址 | 单位地址 | varchar(128) |  |
| company_address_lng | 单位地址经度 | 单位地址经度 | varchar(32) |  |
| company_address_ltt | 单位地址维度 | 单位地址维度 | varchar(32) |  |
| telephone | 单位电话 | 单位电话 | varchar(32) |  |
| vocation | 职业 | 职业 | varchar(32) | 对应字典：profession_type |
| industry | 行业 | 行业 | varchar(32) | 参照国民经济行业分类代码表 |
| job_type | 职务 | 职务 | varchar(16) | 对应字典:job_type_code |
| job_title_type | 职称 | 职称 | varchar(16) | 对应字典：job_title_type |
| join_year | 计入本单位年份 | 计入本单位年份 | shortint |  |
| update_date | 信息更新日期 | 信息更新日期 | date |  |
| time_inst | 插入时间 | 插入时间 | datatime |  |