from grongier.pex import Message
from dataclasses import dataclass
from obj import PermissionObj
from typing import List

@dataclass
class GetPermissionRequest(Message):
    scopes: list

@dataclass
class PermissionResponse(Message):
    permissions: List[PermissionObj] = None

@dataclass
class FilterResource(Message):
    permissions: List[PermissionObj] = None
    resource_str: str = None


@dataclass
class FhirConverterMessage(Message):
    input_filename: str
    input_data: str
    input_data_type: str
    root_template: str

@dataclass
class FhirConverterResponse(Message):
    status: int
    output_data: str
    output_filename: str


@dataclass
class FhirRequest(Message):
    url: str
    resource: str
    method: str
    data: str
    headers: dict

@dataclass
class FhirResponse(Message):
    status_code: int
    content: str
    headers: dict
    resource: str