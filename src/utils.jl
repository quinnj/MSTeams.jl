function normalize_url(url::AbstractString)
    value = strip(String(url))
    isempty(value) && return value
    endswith(value, "/") && return value[1:end-1]
    return value
end

function form_encode(params::AbstractDict)
    parts = String[]
    for (k, v) in params
        push!(parts, "$(HTTP.URIs.escapeuri(string(k)))=$(HTTP.URIs.escapeuri(string(v)))")
    end
    return join(parts, "&")
end

function to_object(value)
    value === nothing && return nothing
    if value isa AbstractDict
        return value
    end
    if value isa NamedTuple
        obj = JSON.Object()
        for (k, v) in pairs(value)
            obj[string(k)] = v
        end
        return obj
    end
    msg = "Unsupported object type: $(typeof(value))"
    throw(ArgumentError(msg))
end

function remove_nothing_values(obj::AbstractDict)
    cleaned = JSON.Object()
    for (k, v) in obj
        v === nothing && continue
        cleaned[string(k)] = v
    end
    return cleaned
end
