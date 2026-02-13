const DEFAULT_MANIFEST_VERSION = "1.19"
const DEFAULT_ACCENT_COLOR = "#FFFFFF"

function manifest_schema_url(version::AbstractString)
    return "https://developer.microsoft.com/json-schemas/teams/v$(version)/MicrosoftTeams.schema.json"
end

function slugify(value::AbstractString)
    lowered = lowercase(String(value))
    buffer = IOBuffer()
    last_dash = false
    for ch in codeunits(lowered)
        if (ch >= UInt8('a') && ch <= UInt8('z')) || (ch >= UInt8('0') && ch <= UInt8('9'))
            write(buffer, ch)
            last_dash = false
        else
            if !last_dash
                write(buffer, UInt8('-'))
                last_dash = true
            end
        end
    end
    result = String(take!(buffer))
    startswith(result, "-") && (result = result[2:end])
    endswith(result, "-") && (result = result[1:end-1])
    isempty(result) && (result = "msteams-app")
    return result
end

function build_manifest(; app_id::AbstractString, bot_id::AbstractString, name_short::AbstractString, description_short::AbstractString, package_name::Union{Nothing, AbstractString}=nothing, name_full::Union{Nothing, AbstractString}=nothing, description_full::Union{Nothing, AbstractString}=nothing, developer_name::AbstractString, developer_website::Union{Nothing, AbstractString}=nothing, developer_privacy::Union{Nothing, AbstractString}=nothing, developer_terms::Union{Nothing, AbstractString}=nothing, version::AbstractString="1.0.0", manifest_version::AbstractString=DEFAULT_MANIFEST_VERSION, accent_color::AbstractString=DEFAULT_ACCENT_COLOR, scopes=["personal", "team", "groupchat"], supports_files::Bool=false, is_notification_only::Bool=false, valid_domains=String[], permissions=["identity", "messageTeamMembers"])
    app_id_value = strip(String(app_id))
    bot_id_value = strip(String(bot_id))
    name_short_value = strip(String(name_short))
    description_short_value = strip(String(description_short))
    isempty(app_id_value) && throw(MSTeamsConfigurationError("app_id is required"))
    isempty(bot_id_value) && throw(MSTeamsConfigurationError("bot_id is required"))
    isempty(name_short_value) && throw(MSTeamsConfigurationError("name_short is required"))
    isempty(description_short_value) && throw(MSTeamsConfigurationError("description_short is required"))
    name_full_value = name_full === nothing ? name_short_value : strip(String(name_full))
    description_full_value = description_full === nothing ? description_short_value : strip(String(description_full))
    package_value = package_name === nothing ? "com.example.$(slugify(name_short_value))" : strip(String(package_name))
    developer_website_value = developer_website === nothing ? "https://example.com" : strip(String(developer_website))
    developer_privacy_value = developer_privacy === nothing ? "https://example.com/privacy" : strip(String(developer_privacy))
    developer_terms_value = developer_terms === nothing ? "https://example.com/terms" : strip(String(developer_terms))
    return JSON.Object(
        "\$schema" => manifest_schema_url(manifest_version),
        "manifestVersion" => String(manifest_version),
        "version" => String(version),
        "id" => app_id_value,
        "packageName" => package_value,
        "developer" => JSON.Object(
            "name" => String(developer_name),
            "websiteUrl" => developer_website_value,
            "privacyUrl" => developer_privacy_value,
            "termsOfUseUrl" => developer_terms_value,
        ),
        "name" => JSON.Object(
            "short" => name_short_value,
            "full" => name_full_value,
        ),
        "description" => JSON.Object(
            "short" => description_short_value,
            "full" => description_full_value,
        ),
        "accentColor" => String(accent_color),
        "icons" => JSON.Object(
            "color" => "color.png",
            "outline" => "outline.png",
        ),
        "bots" => [
            JSON.Object(
                "botId" => bot_id_value,
                "scopes" => scopes,
                "supportsFiles" => supports_files,
                "isNotificationOnly" => is_notification_only,
            ),
        ],
        "permissions" => permissions,
        "validDomains" => valid_domains,
    )
end

const PNG_SIGNATURE = UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]

const CRC32_TABLE = let
    table = Vector{UInt32}(undef, 256)
    for i in 0:255
        c = UInt32(i)
        for _ in 1:8
            if (c & 0x01) == 0x01
                c = xor(UInt32(0xedb88320), c >> 1)
            else
                c >>= 1
            end
        end
        table[i + 1] = c
    end
    table
end

function crc32(data::Vector{UInt8})
    c = UInt32(0xffffffff)
    for byte in data
        idx = Int((xor(c, UInt32(byte)) & 0xff) + 1)
        c = xor(CRC32_TABLE[idx], c >> 8)
    end
    return xor(c, UInt32(0xffffffff))
end

function adler32(data::Vector{UInt8})
    a = UInt32(1)
    b = UInt32(0)
    for byte in data
        a = (a + UInt32(byte)) % UInt32(65521)
        b = (b + a) % UInt32(65521)
    end
    return (b << 16) | a
end

function u32be(value::UInt32)
    return UInt8[
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
    ]
end

function zlib_store(data::Vector{UInt8})
    output = UInt8[]
    push!(output, 0x78, 0x01)
    offset = 1
    remaining = length(data)
    while remaining > 0
        block_len = min(remaining, 65535)
        final_block = remaining <= 65535
        push!(output, final_block ? 0x01 : 0x00)
        push!(output, UInt8(block_len & 0xff), UInt8((block_len >> 8) & 0xff))
        nlen = 0xffff - block_len
        push!(output, UInt8(nlen & 0xff), UInt8((nlen >> 8) & 0xff))
        append!(output, view(data, offset:(offset + block_len - 1)))
        offset += block_len
        remaining -= block_len
    end
    append!(output, u32be(adler32(data)))
    return output
end

function write_chunk(io::IO, chunk_type::AbstractString, data::Vector{UInt8})
    length_value = UInt32(length(data))
    write(io, u32be(length_value))
    type_bytes = Vector{UInt8}(codeunits(String(chunk_type)))
    write(io, type_bytes)
    write(io, data)
    crc = crc32(vcat(type_bytes, data))
    write(io, u32be(crc))
    return
end

function build_scanlines(width::Int, height::Int, pixel_fn::Function)
    row_size = 1 + width * 4
    data = Vector{UInt8}(undef, height * row_size)
    idx = 1
    for y in 1:height
        data[idx] = 0x00
        idx += 1
        for x in 1:width
            r, g, b, a = pixel_fn(x, y)
            data[idx] = UInt8(r)
            data[idx + 1] = UInt8(g)
            data[idx + 2] = UInt8(b)
            data[idx + 3] = UInt8(a)
            idx += 4
        end
    end
    return data
end

function write_png(path::AbstractString, width::Int, height::Int, pixel_fn::Function)
    scanlines = build_scanlines(width, height, pixel_fn)
    compressed = zlib_store(scanlines)
    open(path, "w") do io
        write(io, PNG_SIGNATURE)
        ihdr = UInt8[]
        append!(ihdr, u32be(UInt32(width)))
        append!(ihdr, u32be(UInt32(height)))
        append!(ihdr, UInt8[8, 6, 0, 0, 0])
        write_chunk(io, "IHDR", ihdr)
        write_chunk(io, "IDAT", compressed)
        write_chunk(io, "IEND", UInt8[])
    end
    return
end

function write_default_icons(output_dir::AbstractString)
    color_path = joinpath(output_dir, "color.png")
    outline_path = joinpath(output_dir, "outline.png")
    color_pixel = (x, y) -> (0x2b, 0x7a, 0x78, 0xff)
    outline_pixel = (x, y) -> (x == 1 || y == 1 || x == 32 || y == 32 || x == 192 || y == 192 ? (0x00, 0x00, 0x00, 0xff) : (0x00, 0x00, 0x00, 0x00))
    write_png(color_path, 192, 192, color_pixel)
    write_png(outline_path, 32, 32, outline_pixel)
    return (color_path, outline_path)
end

function write_manifest_bundle(output_dir::AbstractString; app_id::AbstractString, bot_id::AbstractString, name_short::AbstractString, description_short::AbstractString, package_name::Union{Nothing, AbstractString}=nothing, name_full::Union{Nothing, AbstractString}=nothing, description_full::Union{Nothing, AbstractString}=nothing, developer_name::AbstractString, developer_website::Union{Nothing, AbstractString}=nothing, developer_privacy::Union{Nothing, AbstractString}=nothing, developer_terms::Union{Nothing, AbstractString}=nothing, version::AbstractString="1.0.0", manifest_version::AbstractString=DEFAULT_MANIFEST_VERSION, accent_color::AbstractString=DEFAULT_ACCENT_COLOR, scopes=["personal", "team", "groupchat"], supports_files::Bool=false, is_notification_only::Bool=false, valid_domains=String[], permissions=["identity", "messageTeamMembers"], color_icon_path::Union{Nothing, AbstractString}=nothing, outline_icon_path::Union{Nothing, AbstractString}=nothing, bundle_path::Union{Nothing, AbstractString}=nothing)
    mkpath(output_dir)
    manifest = build_manifest(
        app_id=app_id,
        bot_id=bot_id,
        name_short=name_short,
        description_short=description_short,
        package_name=package_name,
        name_full=name_full,
        description_full=description_full,
        developer_name=developer_name,
        developer_website=developer_website,
        developer_privacy=developer_privacy,
        developer_terms=developer_terms,
        version=version,
        manifest_version=manifest_version,
        accent_color=accent_color,
        scopes=scopes,
        supports_files=supports_files,
        is_notification_only=is_notification_only,
        valid_domains=valid_domains,
        permissions=permissions,
    )
    manifest_path = joinpath(output_dir, "manifest.json")
    open(manifest_path, "w") do io
        JSON.print(io, manifest, 2)
    end
    color_output = joinpath(output_dir, "color.png")
    outline_output = joinpath(output_dir, "outline.png")
    if color_icon_path === nothing || outline_icon_path === nothing
        write_default_icons(output_dir)
    end
    if color_icon_path !== nothing
        cp(String(color_icon_path), color_output; force=true)
    end
    if outline_icon_path !== nothing
        cp(String(outline_icon_path), outline_output; force=true)
    end
    zip_path = bundle_path === nothing ? joinpath(output_dir, "$(slugify(name_short))-bundle.zip") : String(bundle_path)
    zip = ZipFile.Writer(zip_path)
    try
        for filename in ("manifest.json", "color.png", "outline.png")
            file_path = joinpath(output_dir, filename)
            file_stream = ZipFile.addfile(zip, filename)
            write(file_stream, read(file_path))
        end
    finally
        close(zip)
    end
    return (manifest=manifest_path, bundle=zip_path, color=color_output, outline=outline_output)
end
